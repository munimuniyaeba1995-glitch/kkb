/* 地図アダプター（MapLibre GL JS 版）
 *
 * アプリ本体（app.js）は地図ライブラリを直接触らず、このインターフェースだけを使う。
 * 将来 Google Earth / CesiumJS などに替えるときは、同じメソッドを持つアダプターを作って
 * window.KNW_createMap を差し替える。
 *
 *   create(el, config) -> Promise<adapter>
 *   adapter.kind            'vector' | 'raster' | 'blank' | 'none'
 *   adapter.styleId         使用中のスタイル名（任意）
 *   adapter.has3D           3D 建物を表示できるか
 *   adapter.attribution     著作権表示（HTML 文字列）
 *   adapter.flyTo({center, zoom, pitch, bearing, duration}) -> Promise<bool>  完了 true / 中断 false
 *   adapter.setCamera({center, zoom, pitch, bearing})        即時に視点変更
 *   adapter.getCamera() -> {center, zoom, pitch, bearing}
 *   adapter.stop()                                           移動を中断
 *   adapter.setStreet(path)   adapter.setStores(stores, visitedSet)   adapter.setCurrent(pos | null)
 *   adapter.set3D(bool)
 *   adapter.onStoreClick = (id) => {}
 *   adapter.onUserMove = () => {}                            利用者が手で地図を動かした
 */
(() => {
  'use strict';
  const OSM_ATTR = '© <a href="https://www.openstreetmap.org/copyright" target="_blank" rel="noopener">OpenStreetMap</a> contributors';

  async function fetchJson(url, ms = 8000) {
    const ctl = new AbortController();
    const timer = setTimeout(() => ctl.abort(), ms);
    try { const r = await fetch(url, { signal: ctl.signal }); if (!r.ok) throw new Error(String(r.status)); return await r.json(); }
    finally { clearTimeout(timer); }
  }
  const probeImage = (url, ms = 8000) => new Promise((res) => {
    const img = new Image(); const t = setTimeout(() => res(false), ms);
    img.onload = () => { clearTimeout(t); res(true); }; img.onerror = () => { clearTimeout(t); res(false); };
    img.src = url;
  });

  const blankStyle = () => ({ version: 8, sources: {}, layers: [{ id: 'bg', type: 'background', paint: { 'background-color': '#0b0a14' } }] });
  const rasterStyle = (tiles) => ({
    version: 8,
    sources: { osm: { type: 'raster', tiles: [tiles], tileSize: 256, maxzoom: 19, attribution: OSM_ATTR } },
    layers: [{ id: 'bg', type: 'background', paint: { 'background-color': '#0b0a14' } }, { id: 'osm', type: 'raster', source: 'osm' }],
  });

  /** スタイルを順に試す: ベクター（3D 建物可）→ ラスター OSM → 無地（デモ） */
  async function pickStyle(cfg) {
    for (const s of cfg.styles) {
      try {
        const style = await fetchJson(s.url);
        if (style?.version === 8 && Array.isArray(style.layers)) return { kind: 'vector', style, id: s.id };
      } catch (e) { console.warn('[KNW] style unavailable:', s.url, e); }
    }
    const probe = cfg.rasterTiles.replace('{z}', '0').replace('{x}', '0').replace('{y}', '0'); // 届くかの確認用に 1 枚だけ
    if (await probeImage(probe)) return { kind: 'raster', style: rasterStyle(cfg.rasterTiles) };
    return { kind: 'blank', style: blankStyle() };
  }

  class MapLibreAdapter {
    static async create(el, cfg) {
      if (!window.maplibregl) throw new Error('MapLibre GL JS を読み込めませんでした');
      const picked = await pickStyle(cfg);
      const map = new maplibregl.Map({
        container: el, style: picked.style, center: [cfg.center.lng, cfg.center.lat], zoom: 11.5, pitch: 0, bearing: 0,
        maxPitch: 85, attributionControl: false, dragRotate: true, touchPitch: true,
      });
      map.addControl(new maplibregl.AttributionControl({ compact: false, customAttribution: picked.kind === 'blank' ? OSM_ATTR : undefined }), 'bottom-right');
      await new Promise((res, rej) => { map.once('load', res); map.once('error', (e) => rej(e.error || new Error('map error'))); setTimeout(res, 12000); });
      const a = new MapLibreAdapter(map, picked.kind, picked.id);
      a._setup3D();
      a._setupOverlay();
      return a;
    }
    constructor(map, kind, styleId) {
      this.map = map; this.kind = kind; this.styleId = styleId || null; this.has3D = false; this.markers = []; this.cur = null;
      this.onStoreClick = null; this.onUserMove = null; this._flight = 0;
      this.attribution = OSM_ATTR + (kind === 'vector' ? ' / <a href="https://openfreemap.org" target="_blank" rel="noopener">OpenFreeMap</a> © <a href="https://www.openmaptiles.org/" target="_blank" rel="noopener">OpenMapTiles</a>' : '');
      for (const ev of ['dragstart', 'rotatestart', 'pitchstart', 'zoomstart']) {
        map.on(ev, (e) => { if (e.originalEvent) this.onUserMove?.(); });
      }
    }
    /** OpenMapTiles 形式の building レイヤーから 3D 建物を作る（スタイルに既にあればそれを使う） */
    _setup3D() {
      const map = this.map, style = map.getStyle();
      this._ext = (style.layers || []).filter((l) => l.type === 'fill-extrusion').map((l) => l.id);
      if (!this._ext.length) {
        const srcId = Object.keys(style.sources || {}).find((k) => style.sources[k].type === 'vector');
        if (srcId) {
          try {
            map.addLayer({
              id: 'knw-buildings-3d', type: 'fill-extrusion', source: srcId, 'source-layer': 'building', minzoom: 14,
              paint: {
                'fill-extrusion-color': '#2a2440',
                'fill-extrusion-height': ['coalesce', ['get', 'render_height'], 6],
                'fill-extrusion-base': ['coalesce', ['get', 'render_min_height'], 0],
                'fill-extrusion-opacity': 0.85,
              },
            });
            this._ext = ['knw-buildings-3d'];
          } catch (e) { console.warn('[KNW] 3D buildings unavailable', e); }
        }
      }
      this.has3D = this._ext.length > 0;
    }
    _setupOverlay() {
      const map = this.map;
      map.addSource('knw-street', { type: 'geojson', data: { type: 'FeatureCollection', features: [] } });
      map.addLayer({ id: 'knw-street-glow', type: 'line', source: 'knw-street', layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#2ee6e6', 'line-width': 12, 'line-opacity': 0.25, 'line-blur': 6 } });
      map.addLayer({ id: 'knw-street-line', type: 'line', source: 'knw-street', layout: { 'line-cap': 'round', 'line-join': 'round' },
        paint: { 'line-color': '#2ee6e6', 'line-width': 3 } });
    }
    set3D(on) { for (const id of this._ext) this.map.setLayoutProperty(id, 'visibility', on ? 'visible' : 'none'); }
    setStreet(path) {
      this.map.getSource('knw-street')?.setData({ type: 'FeatureCollection', features: path.length >= 2
        ? [{ type: 'Feature', properties: {}, geometry: { type: 'LineString', coordinates: path.map((p) => [p.lng, p.lat]) } }] : [] });
    }
    setStores(stores, visited) {
      this.markers.forEach((m) => m.remove()); this.markers = [];
      stores.forEach((s, i) => {
        const el = document.createElement('button');
        el.className = 'store-marker' + (visited.has(s.id) ? ' visited' : '');
        el.type = 'button';
        el.textContent = visited.has(s.id) ? '✓' : String(i + 1);
        el.title = s.name || '名称未登録';
        el.setAttribute('aria-label', `${i + 1}: ${s.name || '名称未登録'}`);
        el.addEventListener('click', (e) => { e.stopPropagation(); this.onStoreClick?.(s.id); });
        this.markers.push(new maplibregl.Marker({ element: el }).setLngLat([s.pos.lng, s.pos.lat]).addTo(this.map));
      });
    }
    setCurrent(p) {
      if (!p) { this.cur?.remove(); this.cur = null; return; }
      if (!this.cur) {
        const el = document.createElement('div'); el.className = 'here-marker'; el.title = '現在地';
        this.cur = new maplibregl.Marker({ element: el }).setLngLat([p.lng, p.lat]).addTo(this.map);
      } else this.cur.setLngLat([p.lng, p.lat]);
    }
    getCamera() { const c = this.map.getCenter(); return { center: { lat: c.lat, lng: c.lng }, zoom: this.map.getZoom(), pitch: this.map.getPitch(), bearing: this.map.getBearing() }; }
    setCamera({ center, zoom, pitch, bearing }) {
      const o = {};
      if (center) o.center = [center.lng, center.lat];
      if (zoom != null) o.zoom = zoom; if (pitch != null) o.pitch = pitch; if (bearing != null) o.bearing = bearing;
      this.map.jumpTo(o);
    }
    flyTo({ center, zoom, pitch, bearing, duration = 3 }) {
      const id = ++this._flight, map = this.map;
      return new Promise((res) => {
        const done = () => res(id === this._flight);
        map.once('moveend', done);
        map.flyTo({ center: [center.lng, center.lat], zoom, pitch, bearing, duration: duration * 1000, essential: true, curve: 1.2 });
      });
    }
    stop() { this._flight++; this.map.stop(); }
  }

  /** 地図が使えないとき用。同じインターフェースで何もしない（デモ画面は app.js が出す）。 */
  class NullAdapter {
    constructor() { this.kind = 'none'; this.has3D = false; this.attribution = OSM_ATTR; this._cam = { center: null, zoom: 0, pitch: 0, bearing: 0 }; this._flight = 0; }
    flyTo(c) { const id = ++this._flight; Object.assign(this._cam, c); return new Promise((r) => setTimeout(() => r(id === this._flight), 400)); }
    setCamera(c) { Object.assign(this._cam, c); }
    getCamera() { return this._cam; }
    stop() { this._flight++; }
    setStreet() {} setStores() {} setCurrent() {} set3D() {}
  }

  window.KNW_createMap = async (el, cfg) => {
    try { return await MapLibreAdapter.create(el, cfg); }
    catch (e) { console.warn('[KNW] map unavailable, showing demo screen', e); return new NullAdapter(); }
  };
})();

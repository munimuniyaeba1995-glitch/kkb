/* KOZA NIGHT WALK — 本体
 *
 * 実データ: Google Photorealistic 3D Tiles / Street View / Places / Directions
 * 演出    : カメラワーク、夜景フィルター、UI
 * 店舗の位置・営業時間・写真は実行時に Google から取得し、取れないものは「確認できませんでした」と出す。
 */
(() => {
  'use strict';
  const DATA = window.KNW_DATA;
  const $ = (id) => document.getElementById(id);
  const LS_KEY = 'knw.apiKey';
  const LS_VISITED = 'knw.visited';

  // ---------- 小道具 ----------
  const rad = (d) => (d * Math.PI) / 180;
  const deg = (r) => (r * 180) / Math.PI;
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));
  const lit = (p) => (typeof p.lat === 'function' ? { lat: p.lat(), lng: p.lng() } : { lat: p.lat, lng: p.lng });
  const withTimeout = (p, ms, fallback) => Promise.race([p, sleep(ms).then(() => fallback)]);

  /** 2 点間距離 (m) */
  function dist(a, b) {
    const R = 6371008.8;
    const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  /** a から b への方位 (度, 北=0 時計回り) */
  function bearing(a, b) {
    const y = Math.sin(rad(b.lng - a.lng)) * Math.cos(rad(b.lat));
    const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(rad(b.lng - a.lng));
    return (deg(Math.atan2(y, x)) + 360) % 360;
  }
  const angDiff = (a, b) => Math.abs(((a - b + 540) % 360) - 180);
  const signedDiff = (from, to) => ((to - from + 540) % 360) - 180;

  /** 道順ポリライン上の計算（局所平面近似。数百 m の範囲なので十分） */
  const Path = {
    xy(p, o) { return { x: rad(p.lng - o.lng) * 6371008.8 * Math.cos(rad(o.lat)), y: rad(p.lat - o.lat) * 6371008.8 }; },
    /** 点 p を線に射影: { s: 起点からの道のり m, d: 線までの距離 m } */
    project(path, p) {
      let best = { s: 0, d: Infinity }, acc = 0;
      for (let i = 0; i < path.length - 1; i++) {
        const o = path[i], b = Path.xy(path[i + 1], o), q = Path.xy(p, o);
        const len2 = b.x * b.x + b.y * b.y, len = Math.sqrt(len2);
        const t = len2 ? Math.max(0, Math.min(1, (q.x * b.x + q.y * b.y) / len2)) : 0;
        const d = Math.hypot(q.x - t * b.x, q.y - t * b.y);
        if (d < best.d) best = { s: acc + t * len, d };
        acc += len;
      }
      if (path.length === 1) best = { s: 0, d: dist(path[0], p) };
      return best;
    },
    length(path) { let L = 0; for (let i = 0; i < path.length - 1; i++) L += dist(path[i], path[i + 1]); return L; },
    /** 起点から道のり s の地点 */
    at(path, s) {
      if (path.length === 1 || s <= 0) return path[0];
      let acc = 0;
      for (let i = 0; i < path.length - 1; i++) {
        const len = dist(path[i], path[i + 1]);
        if (acc + len >= s && len > 0) {
          const t = (s - acc) / len;
          return { lat: path[i].lat + (path[i + 1].lat - path[i].lat) * t, lng: path[i].lng + (path[i + 1].lng - path[i].lng) * t };
        }
        acc += len;
      }
      return path[path.length - 1];
    },
  };

  // ---------- 状態 ----------
  const S = {
    key: new URLSearchParams(location.search).get('key') || localStorage.getItem(LS_KEY) || '',
    mode: 'free',
    view: 'aerial',
    stores: DATA.stores.map((s) => ({ ...s, place: null, pos: null, resolved: false, error: null })),
    order: [],          // 位置が確認できた店舗（巡る順）
    path: [],           // 実際の道順（Directions）。取れない場合は店舗間を結ぶ概略線
    pathApprox: true,
    entrance: null,
    visited: new Set(JSON.parse(localStorage.getItem(LS_VISITED) || '[]')),
    aerial: null,       // CesiumAerial | MapAerial
    aerialKind: null,   // '3d' | '2d' | null
    ground: null,
    googleReady: false,
    tour: null,         // { token, paused, idx, waitNext }
    openStore: null,
  };

  // ---------- UI 基本 ----------
  function setStatus(msg) { const el = $('status'); el.textContent = msg || ''; el.hidden = !msg; }
  let statusTimer;
  function flash(msg, ms = 5000) { setStatus(msg); clearTimeout(statusTimer); statusTimer = setTimeout(() => setStatus(''), ms); }
  function caption(text) { $('caption').textContent = text || ''; }
  function setMode(mode) {
    S.mode = mode;
    document.body.classList.toggle('mode-free', mode === 'free');
    document.body.classList.toggle('mode-tour', mode === 'tour');
    $('modeFree').setAttribute('aria-selected', mode === 'free');
    $('modeTour').setAttribute('aria-selected', mode === 'tour');
    if (mode === 'free') caption('');
    else if (!S.tour) caption('スタートで上空からサンシティ通りへ');
  }
  function setView(view) {
    S.view = view;
    document.body.classList.toggle('view-aerial', view === 'aerial');
    document.body.classList.toggle('view-ground', view === 'ground');
    $('ground').hidden = view !== 'ground';
    $('minimap').hidden = view !== 'ground';
    if (view === 'aerial') $('where').textContent = '';
  }
  async function crossfade(fn) {
    $('fade').classList.add('on');
    await sleep(600);
    try { return await fn(); } finally { await sleep(150); $('fade').classList.remove('on'); }
  }
  function markVisited(store) {
    if (S.visited.has(store.id)) return;
    S.visited.add(store.id);
    localStorage.setItem(LS_VISITED, JSON.stringify([...S.visited]));
    refreshMarkers();
    renderList();
  }
  function refreshMarkers() {
    S.aerial?.setStores(S.order, S.visited);
    S.ground?.setStores(S.order, S.visited);
  }

  // ---------- Google Maps JS ----------
  function loadGoogle(key) {
    return new Promise((resolve, reject) => {
      if (window.google?.maps?.importLibrary) return resolve();
      window.gm_authFailure = () => { setStatus('Google の認証に失敗しました。API キーと有効化した API を確認してください。'); };
      window.__knwGoogleReady = () => resolve();
      const s = document.createElement('script');
      s.src = `https://maps.googleapis.com/maps/api/js?key=${encodeURIComponent(key)}&v=weekly&loading=async&language=ja&region=JP&callback=__knwGoogleReady`;
      s.async = true;
      s.onerror = () => reject(new Error('Maps JavaScript API を読み込めませんでした'));
      document.head.appendChild(s);
    });
  }

  const PLACE_FIELDS = ['id', 'displayName', 'location', 'formattedAddress', 'regularOpeningHours', 'photos',
    'googleMapsURI', 'businessStatus', 'editorialSummary', 'primaryTypeDisplayName'];

  /** シード店舗を Places で解決する。名前が一致し、沖縄市中心部にあるものだけ採用。 */
  async function resolveStore(store) {
    const { Place } = await google.maps.importLibrary('places');
    try {
      const { places } = await Place.searchByText({
        textQuery: store.query, fields: PLACE_FIELDS, language: 'ja', region: 'jp', maxResultCount: 3,
        locationBias: { center: DATA.overview, radius: DATA.biasRadius },
      });
      const hit = (places || []).find((p) => {
        const name = p.displayName || '';
        return p.location && name.includes(store.match) && dist(lit(p.location), DATA.overview) <= DATA.maxDistance;
      });
      if (!hit) { store.error = 'Google マップで該当する店舗を確認できませんでした'; return; }
      store.place = hit; store.pos = lit(hit.location); store.resolved = true;
    } catch (e) {
      store.error = 'Places API から取得できませんでした';
      console.warn('[KNW] place lookup failed', store.id, e);
    }
  }

  async function resolveEntrance() {
    try {
      const { Place } = await google.maps.importLibrary('places');
      const { places } = await Place.searchByText({
        textQuery: DATA.entranceQuery, fields: ['location', 'displayName'], language: 'ja', maxResultCount: 1,
        locationBias: { center: DATA.overview, radius: DATA.biasRadius },
      });
      const p = places?.[0];
      if (p?.location && dist(lit(p.location), DATA.overview) <= DATA.maxDistance) S.entrance = lit(p.location);
    } catch (e) { console.warn('[KNW] entrance lookup failed', e); }
  }

  /** 巡る順を決める: 最も離れた 2 店のうち入口（胡屋十字路）に近い方から、近い順に。 */
  function decideOrder() {
    const ok = S.stores.filter((s) => s.resolved);
    if (ok.length < 2) { S.order = ok; return; }
    let a = ok[0], b = ok[1], far = -1;
    for (const p of ok) for (const q of ok) { const d = dist(p.pos, q.pos); if (d > far) { far = d; a = p; b = q; } }
    let start = a;
    if (S.entrance && dist(S.entrance, b.pos) < dist(S.entrance, a.pos)) start = b;
    S.order = [...ok].sort((p, q) => dist(start.pos, p.pos) - dist(start.pos, q.pos));
  }

  /** 実際の道路に沿った徒歩ルートを Directions から取得。失敗時は概略線にして明示する。 */
  async function buildPath() {
    const pts = S.order.map((s) => s.pos);
    S.path = pts.slice(); S.pathApprox = true;
    if (!pts.length) return;
    const origin = S.entrance && dist(S.entrance, pts[0]) < 800 ? S.entrance : pts[0];
    if (origin === pts[0] && pts.length < 2) return;
    try {
      const { DirectionsService } = await google.maps.importLibrary('routes');
      const stops = origin === pts[0] ? pts.slice(1) : pts;
      const res = await new DirectionsService().route({
        origin, destination: stops[stops.length - 1],
        waypoints: stops.slice(0, -1).map((p) => ({ location: p, stopover: true })),
        travelMode: 'WALKING',
      });
      const path = [];
      for (const leg of res.routes[0].legs) for (const step of leg.steps) for (const p of step.path) path.push(lit(p));
      if (path.length >= 2) { S.path = path; S.pathApprox = false; }
    } catch (e) {
      console.warn('[KNW] directions failed; using straight segments', e);
      if (origin !== pts[0]) S.path = [origin, ...pts];
    }
    // 道のり順に並べ直す（ルートに沿って手前から）
    S.order.sort((p, q) => Path.project(S.path, p.pos).s - Path.project(S.path, q.pos).s);
  }

  // ---------- 上空ビュー: Cesium + Google Photorealistic 3D Tiles ----------
  class CesiumAerial {
    static async create(el, key) {
      if (!window.Cesium) throw new Error('CesiumJS を読み込めませんでした');
      const C = window.Cesium;
      // Viewer を先に作る（WebGL の上限値が確定してからタイルセットを作る必要がある）
      const viewer = new C.Viewer(el, {
        baseLayer: false, baseLayerPicker: false, geocoder: false, homeButton: false, sceneModePicker: false,
        navigationHelpButton: false, animation: false, timeline: false, fullscreenButton: false,
        infoBox: false, selectionIndicator: false,
      });
      let tileset;
      try {
        tileset = await C.Cesium3DTileset.fromUrl(
          `https://tile.googleapis.com/v1/3dtiles/root.json?key=${encodeURIComponent(key)}`,
          { showCreditsOnScreen: true });
      } catch (e) { viewer.destroy(); throw e; }
      viewer.scene.globe.show = false; // 地形・建物は Google の 3D タイルのみを使う
      viewer.scene.primitives.add(tileset);
      const a = new CesiumAerial(viewer, tileset);
      a.fly(DATA.overview, { heading: 0, pitch: -90, range: 9000, duration: 0 }); // 最初から沖縄市上空を映す
      // 一定時間タイルが 1 枚も届かなければ 3D 利用不可とみなす
      a.firstTile = new Promise((res) => {
        const off = tileset.tileLoad.addEventListener(() => { off(); res(true); });
      });
      return a;
    }
    constructor(viewer, tileset) {
      this.C = window.Cesium; this.viewer = viewer; this.tileset = tileset;
      this.groundH = null; this.storeEntities = []; this.onStoreClick = null;
      const C = this.C;
      viewer.screenSpaceEventHandler.setInputAction((e) => {
        const picked = viewer.scene.pick(e.position);
        const id = picked?.id?.knwStoreId;
        if (id && this.onStoreClick) this.onStoreClick(id);
      }, C.ScreenSpaceEventType.LEFT_CLICK);
    }
    destroy() { this.viewer.destroy(); }
    /** 3D タイル表面の高さ（楕円体高）。取れなければ null。 */
    async sampleGround(p) {
      const C = this.C;
      try {
        const r = await withTimeout(this.viewer.scene.sampleHeightMostDetailed([C.Cartographic.fromDegrees(p.lng, p.lat)]), 10000, null);
        const h = r?.[0]?.height;
        return Number.isFinite(h) ? h : null;
      } catch { return null; }
    }
    /** 地表の楕円体高。未取得の間はコザ周辺の目安値（概算）を使い、低空には降りない。 */
    h() { return this.groundH ?? 120; }
    /** ドローン風: target を見ながら heading/pitch/range の位置へ滑らかに移動 */
    fly(target, { heading = 0, pitch = -45, range = 1000, duration = 3 }) {
      const C = this.C;
      const center = C.Cartesian3.fromDegrees(target.lng, target.lat, this.h());
      return new Promise((res) => this.viewer.camera.flyToBoundingSphere(new C.BoundingSphere(center, 1), {
        offset: new C.HeadingPitchRange(rad(heading), rad(pitch), range), duration,
        easingFunction: C.EasingFunction.QUADRATIC_IN_OUT,
        complete: () => res(true), cancel: () => res(false),
      }));
    }
    cancel() { this.viewer.camera.cancelFlight(); }
    setStores(stores, visited) {
      const C = this.C, ents = this.viewer.entities;
      this.storeEntities.forEach((e) => ents.remove(e)); this.storeEntities = [];
      stores.forEach((s, i) => {
        const done = visited.has(s.id);
        const e = ents.add({
          position: C.Cartesian3.fromDegrees(s.pos.lng, s.pos.lat, this.h() + 14),
          point: { pixelSize: 16, color: C.Color.fromCssColorString(done ? '#5dfc9b' : '#ff3d9a'), outlineColor: C.Color.WHITE, outlineWidth: 2, disableDepthTestDistance: Number.POSITIVE_INFINITY },
          label: { text: `${i + 1}. ${s.name}${done ? ' ✓' : ''}`, font: '600 14px sans-serif', fillColor: C.Color.WHITE,
            outlineColor: C.Color.BLACK, outlineWidth: 4, style: C.LabelStyle.FILL_AND_OUTLINE,
            pixelOffset: new C.Cartesian2(0, -22), disableDepthTestDistance: Number.POSITIVE_INFINITY,
            distanceDisplayCondition: new C.DistanceDisplayCondition(0, 2500) },
        });
        e.knwStoreId = s.id;
        this.storeEntities.push(e);
      });
    }
    setPath(path) {
      const C = this.C;
      if (this.pathEntity) this.viewer.entities.remove(this.pathEntity);
      if (path.length < 2) return;
      const pos = path.map((p) => C.Cartesian3.fromDegrees(p.lng, p.lat, this.h() + 2));
      const mat = new C.PolylineGlowMaterialProperty({ glowPower: 0.25, color: C.Color.fromCssColorString('#2ee6e6') });
      this.pathEntity = this.viewer.entities.add({ polyline: { positions: pos, width: 8, material: mat, depthFailMaterial: mat } });
    }
    setCurrent(p) {
      const C = this.C;
      if (!p) { if (this.cur) { this.viewer.entities.remove(this.cur); this.cur = null; } return; }
      const pos = C.Cartesian3.fromDegrees(p.lng, p.lat, this.h() + 4);
      if (!this.cur) this.cur = this.viewer.entities.add({ position: pos, point: { pixelSize: 12, color: C.Color.fromCssColorString('#ffb347'), outlineColor: C.Color.WHITE, outlineWidth: 2, disableDepthTestDistance: Number.POSITIVE_INFINITY } });
      else this.cur.position = pos;
    }
  }

  // ---------- 上空ビュー（フォールバック）: 通常の Google マップ ----------
  class MapAerial {
    static async create(el) {
      const { Map } = await google.maps.importLibrary('maps');
      const map = new Map(el, {
        center: DATA.overview, zoom: 13, mapTypeId: 'hybrid', disableDefaultUI: true, zoomControl: true,
        gestureHandling: 'greedy', isFractionalZoomEnabled: true, tilt: 0,
      });
      return new MapAerial(map);
    }
    constructor(map) { this.map = map; this.markers = []; this.onStoreClick = null; this.flight = 0; }
    destroy() {}
    async sampleGround() { return null; }
    fly(target, { range = 1000, duration = 3 }) {
      const zoomTo = Math.max(3, Math.min(20, Math.log2(4.0e7 / range)));
      const id = ++this.flight, map = this.map;
      const z0 = map.getZoom(), c0 = lit(map.getCenter()), t0 = performance.now();
      return new Promise((res) => {
        const tick = (now) => {
          if (id !== this.flight) return res(false);
          let t = Math.min(1, (now - t0) / (duration * 1000));
          t = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
          map.moveCamera({ zoom: z0 + (zoomTo - z0) * t, center: { lat: c0.lat + (target.lat - c0.lat) * t, lng: c0.lng + (target.lng - c0.lng) * t } });
          if (t < 1) requestAnimationFrame(tick); else res(true);
        };
        requestAnimationFrame(tick);
      });
    }
    cancel() { this.flight++; }
    setStores(stores, visited) {
      this.markers.forEach((m) => m.setMap(null)); this.markers = [];
      stores.forEach((s, i) => {
        const m = new google.maps.Marker({ map: this.map, position: s.pos, title: s.name,
          label: { text: visited.has(s.id) ? '✓' : String(i + 1), color: '#fff', fontWeight: '700' } });
        m.addListener('click', () => this.onStoreClick?.(s.id));
        this.markers.push(m);
      });
    }
    setPath(path) {
      this.line?.setMap(null);
      if (path.length < 2) return;
      this.line = new google.maps.Polyline({ map: this.map, path, strokeColor: '#2ee6e6', strokeWeight: 5, strokeOpacity: 0.85 });
    }
    setCurrent(p) {
      if (!p) { this.cur?.setMap(null); this.cur = null; return; }
      if (!this.cur) this.cur = new google.maps.Marker({ map: this.map, position: p, title: '現在地', zIndex: 99,
        icon: { path: google.maps.SymbolPath.CIRCLE, scale: 7, fillColor: '#ffb347', fillOpacity: 1, strokeColor: '#fff', strokeWeight: 2 } });
      else this.cur.setPosition(p);
    }
  }

  // ---------- 地上ビュー: Google Street View ----------
  class Ground {
    static async create(el, miniEl) {
      const [{ StreetViewPanorama, StreetViewService }, { Map }] = await Promise.all([
        google.maps.importLibrary('streetView'), google.maps.importLibrary('maps')]);
      const pano = new StreetViewPanorama(el, {
        visible: false, addressControl: false, fullscreenControl: false, motionTracking: false, motionTrackingControl: false,
        zoomControl: false, panControl: false, linksControl: true, clickToGo: true, showRoadLabels: true, enableCloseButton: false,
      });
      const mini = new Map(miniEl, { center: DATA.overview, zoom: 18, disableDefaultUI: true, gestureHandling: 'none', clickableIcons: false });
      mini.setStreetView(pano); // ミニマップに現在地（ペグマン）を表示
      return new Ground(pano, new StreetViewService(), mini);
    }
    constructor(pano, svc, mini) {
      this.pano = pano; this.svc = svc; this.mini = mini; this.markers = []; this.onMove = null; this.onStoreClick = null;
      pano.addListener('position_changed', () => {
        const p = this.position(); if (!p) return;
        this.mini.setCenter(p); this.onMove?.(p);
      });
    }
    position() { const p = this.pano.getPosition(); return p ? lit(p) : null; }
    /** 指定地点の最寄りパノラマを探す。無ければ null（推測の映像は出さない）。 */
    async find(p, radius = 50) {
      try {
        const { data } = await this.svc.getPanorama({ location: p, radius, preference: 'nearest' });
        return data?.location?.pano ? { pano: data.location.pano, pos: lit(data.location.latLng) } : null;
      } catch { return null; }
    }
    async enter(p, heading) {
      const hit = (await this.find(p, 50)) || (await this.find(p, 150));
      if (!hit) return false;
      this.pano.setPano(hit.pano);
      this.pano.setPov({ heading: heading ?? 0, pitch: 0 });
      this.pano.setZoom(0);
      this.pano.setVisible(true);
      this.mini.setCenter(hit.pos);
      await this.waitLinks();
      return true;
    }
    leave() { this.pano.setVisible(false); }
    waitLinks() {
      return withTimeout(new Promise((res) => {
        const l = this.pano.addListener('links_changed', () => { l.remove(); res(); });
      }), 2500);
    }
    /** 視線を滑らかに回す */
    async turnTo(heading, pitch = 0, gate) {
      const pov = this.pano.getPov();
      const dh = signedDiff(pov.heading, heading), dp = pitch - pov.pitch;
      const steps = Math.max(1, Math.round(Math.abs(dh) / 3));
      for (let i = 1; i <= steps; i++) {
        if (gate) await gate();
        const t = i / steps, e = t < 0.5 ? 2 * t * t : 1 - (-2 * t + 2) ** 2 / 2;
        this.pano.setPov({ heading: pov.heading + dh * e, pitch: pov.pitch + dp * e });
        await sleep(16);
      }
    }
    /** ストリートビューの接続（＝実際の道）をたどって target へ歩く。path があれば道順に沿う。 */
    async walkTo(target, path, gate) {
      const seen = new Set();
      let best = Infinity;
      for (let i = 0; i < 80; i++) {
        await gate();
        const pos = this.position(); if (!pos) break;
        const d = dist(pos, target);
        if (d < 9) break;
        if (d < best) best = d; else if (d > best + 12) break; // 行き過ぎ
        let aim = target;
        if (path.length >= 2) {
          const sp = Path.project(path, pos), st = Path.project(path, target);
          if (sp.d < 40 && Math.abs(st.s - sp.s) > 25) aim = Path.at(path, sp.s + Math.sign(st.s - sp.s) * 25);
        }
        const want = bearing(pos, aim);
        const links = (this.pano.getLinks() || []).filter((l) => l && l.pano && !seen.has(l.pano));
        links.sort((a, b) => angDiff(a.heading, want) - angDiff(b.heading, want));
        const next = links[0];
        if (!next || angDiff(next.heading, want) > 100) break; // これ以上近づける道がない
        await this.turnTo(next.heading, 0, gate);
        seen.add(this.pano.getPano());
        const moved = new Promise((res) => { const l = this.pano.addListener('position_changed', () => { l.remove(); res(); }); });
        this.pano.setPano(next.pano);
        await withTimeout(moved, 3000);
        await this.waitLinks();
        await sleep(450);
      }
      const pos = this.position();
      if (pos) await this.turnTo(bearing(pos, target), 4, gate); // 店（看板）の方向を向く
      return pos ? dist(pos, target) : Infinity;
    }
    setStores(stores, visited) {
      this.markers.forEach((m) => m.setMap(null)); this.markers = [];
      stores.forEach((s, i) => {
        const label = { text: visited.has(s.id) ? '✓' : String(i + 1), color: '#fff', fontWeight: '700' };
        const onPano = new google.maps.Marker({ map: this.pano, position: s.pos, title: s.name, label });
        onPano.addListener('click', () => this.onStoreClick?.(s.id));
        const onMini = new google.maps.Marker({ map: this.mini, position: s.pos, title: s.name, label });
        this.markers.push(onPano, onMini);
      });
    }
    setPath(path) {
      this.line?.setMap(null);
      if (path.length >= 2) this.line = new google.maps.Polyline({ map: this.mini, path, strokeColor: '#2ee6e6', strokeWeight: 4 });
    }
  }

  // ---------- 店舗パネル ----------
  const mapsLink = (s) => s.place?.googleMapsURI
    || `https://www.google.com/maps/search/?api=1&query=${encodeURIComponent(s.name + ' 沖縄市中央')}`;

  function hoursHtml(s) {
    const lines = s.place?.regularOpeningHours?.weekdayDescriptions;
    if (!lines?.length) return '<p class="unknown">営業時間は確認できませんでした（Google マップに登録がない、または未取得）。来店前に店舗へご確認ください。</p>';
    const today = (new Date().getDay() + 6) % 7; // weekdayDescriptions は月曜始まり
    return `<ul class="hours">${lines.map((l, i) => `<li class="${i === today ? 'today' : ''}">${esc(l)}</li>`).join('')}</ul>
      <p class="fine">出典: Google マップ登録情報（変更されている場合があります）</p>`;
  }
  function photosHtml(s) {
    const photos = (s.place?.photos || []).slice(0, 6);
    if (!photos.length) return '<p class="unknown">写真は取得できませんでした。</p>';
    const figs = photos.map((ph) => {
      let url = ''; try { url = ph.getURI({ maxWidth: 640, maxHeight: 480 }); } catch { /* noop */ }
      const by = (ph.authorAttributions || []).map((a) => a.displayName).filter(Boolean).join(', ');
      return url ? `<figure><img loading="lazy" src="${esc(url)}" alt="${esc(s.name)} の写真"><figcaption>${by ? '撮影: ' + esc(by) : ''}</figcaption></figure>` : '';
    }).join('');
    return `<div class="photos">${figs}</div><p class="fine">Google マップ掲載写真（料理・ドリンク・店内など。内容の自動分類はしていません）</p>`;
  }
  function badgesHtml(s) {
    const b = [];
    if (s.resolved) b.push('<span class="badge ok">位置: Google Places で確認</span>');
    else b.push('<span class="badge warn">位置: 未確認（地図に表示していません）</span>');
    const st = s.place?.businessStatus;
    if (st === 'OPERATIONAL') b.push('<span class="badge ok">営業中の登録</span>');
    else if (st === 'CLOSED_TEMPORARILY') b.push('<span class="badge warn">臨時休業の登録</span>');
    else if (st === 'CLOSED_PERMANENTLY') b.push('<span class="badge warn">閉業の登録</span>');
    if (s.auto) b.push('<span class="badge warn">Google マップから自動取得</span>');
    if (S.visited.has(s.id)) b.push('<span class="badge visit">訪問済み ✓</span>');
    return `<div class="badges">${b.join('')}</div>`;
  }

  async function openPanel(store, { visit = true } = {}) {
    S.openStore = store;
    if (visit && store.resolved) markVisited(store);
    const gName = store.place?.displayName;
    const addr = store.place?.formattedAddress || store.address;
    const feats = [...(store.features || [])];
    if (store.place?.editorialSummary) feats.push(`${store.place.editorialSummary}（Google マップの概要）`);
    const srcs = (store.sources || []).map((x) => `<a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(x.label)}</a>`).join(' / ');
    $('panelBody').innerHTML = `
      <h2>${esc(store.name)}</h2>
      ${gName && gName !== store.name ? `<p class="fine">Google マップ上の名称: ${esc(gName)}</p>` : ''}
      ${badgesHtml(store)}
      <p>${addr ? esc(addr) : '<span class="unknown">住所は確認できませんでした</span>'}</p>
      ${store.error ? `<p class="unknown">${esc(store.error)}</p>` : ''}
      <h3>外観（ストリートビュー実写）</h3>
      <div id="exterior"></div><p class="fine" id="exteriorNote"></p>
      <h3>料理・ドリンクなどの写真</h3>${photosHtml(store)}
      <h3>営業時間</h3>${hoursHtml(store)}
      <h3>店舗の特徴</h3>
      ${feats.length ? `<ul class="features">${feats.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>` : '<p class="unknown">特徴は確認できませんでした。</p>'}
      ${srcs ? `<p class="fine">出典: ${srcs}</p>` : ''}
      ${store.note ? `<p class="fine">${esc(store.note)}</p>` : ''}
      <div class="actions">
        <a class="btn" href="${esc(mapsLink(store))}" target="_blank" rel="noopener">Google マップで開く</a>
        ${store.resolved && S.mode === 'free' ? '<button id="panelWalk">ここを歩く</button>' : ''}
      </div>`;
    $('panel').hidden = false;
    $('list').hidden = true;
    $('panelWalk')?.addEventListener('click', () => { closePanel(); walkFree(store.pos, store.pos); });
    showExterior(store);
  }
  function closePanel() { $('panel').hidden = true; S.openStore = null; }

  /** 外観: 店舗前のストリートビュー実写を店の方向に向けて表示。無ければ無いと出す。 */
  async function showExterior(store) {
    const el = $('exterior'), note = $('exteriorNote');
    if (!el) return;
    const none = (msg) => { el.hidden = true; note.className = 'unknown'; note.textContent = msg; };
    if (!S.googleReady || !S.ground) return none('外観は表示できません（API キー未設定、または読み込み失敗）。');
    if (!store.resolved) return none('位置が未確認のため外観は表示していません。');
    const hit = await S.ground.find(store.pos, 40);
    if (S.openStore !== store) return;
    if (!hit) return none('この店舗前のストリートビューは見つかりませんでした。');
    const { StreetViewPanorama } = await google.maps.importLibrary('streetView');
    new StreetViewPanorama(el, { pano: hit.pano, pov: { heading: bearing(hit.pos, store.pos), pitch: 5 }, zoom: 0,
      disableDefaultUI: true, clickToGo: false, linksControl: false, showRoadLabels: false });
    note.textContent = `店舗から約 ${Math.round(dist(hit.pos, store.pos))} m の地点から店舗方向を向いた実写（撮影時期は Google に依存）`;
  }

  function renderList() {
    const all = [...S.order, ...S.stores.filter((s) => !s.resolved)];
    $('listBody').innerHTML = all.map((s) => `
      <li data-id="${esc(s.id)}" class="${S.visited.has(s.id) ? 'visited' : ''}" tabindex="0">
        <b>${esc(s.name)}</b>${S.visited.has(s.id) ? ' <span class="badge visit">訪問済み</span>' : ''}
        <small>${esc(s.place?.formattedAddress || s.address || '住所未確認')}${s.resolved ? '' : ' ・ 位置未確認'}${s.auto ? ' ・ 自動取得' : ''}</small>
      </li>`).join('');
  }

  // ---------- 視点の移動 ----------
  function nextStoreInfo(pos) {
    const next = S.order.find((s) => !S.visited.has(s.id)) || null;
    $('where').textContent = `現在地 ${pos.lat.toFixed(5)}, ${pos.lng.toFixed(5)}`
      + (next ? ` ・ 次の未訪問店「${next.name}」まで約 ${Math.round(dist(pos, next.pos))} m` : ' ・ 全店訪問済み');
  }

  async function toGround(p, lookAt) {
    if (!S.ground) { flash('ストリートビューを利用できません（API キーを設定してください）。'); return false; }
    const heading = lookAt && dist(p, lookAt) > 3 ? bearing(p, lookAt) : undefined;
    const ok = await crossfade(async () => {
      const entered = await S.ground.enter(p, heading);
      if (entered) setView('ground');
      return entered;
    });
    if (!ok) flash('この地点のストリートビューは見つかりませんでした。上空ビューのまま表示します。');
    return ok;
  }
  async function toAerial() {
    await crossfade(async () => { S.ground?.leave(); setView('aerial'); });
  }
  /** フリーモードで地上へ */
  async function walkFree(p, lookAt) {
    if (!p) return flash('位置を確認できた店舗がないため、地上ビューを開始できません。');
    await toGround(p, lookAt);
  }
  /** ツアーの地上開始地点: 1 軒目の約 70 m 手前（道順上）。 */
  function groundStart() {
    const first = S.order[0];
    if (!first) return null;
    if (S.path.length < 2) return { p: first.pos, look: first.pos };
    const s = Path.project(S.path, first.pos).s;
    const p = Path.at(S.path, Math.max(0, s - 70));
    return { p, look: Path.at(S.path, Math.max(0, s - 70) + 20) };
  }

  // ---------- 自動飲み歩きツアー ----------
  class Cancelled extends Error {}
  function tourButtons() {
    const t = S.tour;
    $('btnStart').hidden = !!t;
    $('btnPause').hidden = !t || t.paused || !!t.waitNext;
    $('btnResume').hidden = !t || !t.paused;
    $('btnNext').hidden = !t || !t.waitNext;
    $('btnEnd').hidden = !t;
  }
  async function startTour() {
    if (S.tour) return;
    if (!S.order.length) return flash('位置を確認できた店舗がないため、ツアーを開始できません。API キーと Places API (New) を確認してください。', 8000);
    const t = S.tour = { paused: false, waitNext: null, cancelled: false };
    const gate = async () => {
      while (t.paused && !t.cancelled) await sleep(120);
      if (t.cancelled) throw new Cancelled();
    };
    const pause = async (ms) => { const end = Date.now() + ms; while (Date.now() < end) { await gate(); await sleep(80); } };
    /** 上空カメラの 1 区間。中断されたら再開時にやり直す。 */
    const fly = async (target, opt) => {
      for (;;) { await gate(); const done = await S.aerial.fly(target, opt); if (done) return; await sleep(50); }
    };
    tourButtons(); closePanel();
    try {
      const start = groundStart();
      const first = S.order[0];
      const streetHeading = bearing(start.p, first.pos) || 0;
      if (S.view === 'ground') await toAerial();

      // 1) 沖縄市上空 → 2) 降下 → 3) 通りへ接近（ドローン風）
      if (S.aerial) {
        caption('沖縄市 上空');
        await S.aerial.fly(DATA.overview, { heading: 0, pitch: -90, range: 9000, duration: 0 });
        await pause(1800);
        caption('コザへ降下中…');
        await fly(start.p, { heading: streetHeading - 60, pitch: -65, range: 2600, duration: 6 });
        await fly(start.p, { heading: streetHeading - 25, pitch: -42, range: 650, duration: 5 });
        caption('サンシティ通りへ');
        // 地表の高さを 3D タイルから実測できた場合だけ低空まで降りる（地面へのめり込み防止）
        if (S.aerial.groundH == null) {
          const h = await S.aerial.sampleGround(start.p);
          if (h != null) { S.aerial.groundH = h; S.aerial.setPath(S.path); refreshMarkers(); }
        }
        if (S.aerialKind === '2d' || S.aerial.groundH != null) {
          await fly(start.p, { heading: streetHeading, pitch: -24, range: 150, duration: 5 });
          await fly(start.p, { heading: streetHeading, pitch: -12, range: 45, duration: 3 });
        } else {
          await fly(start.p, { heading: streetHeading, pitch: -35, range: 320, duration: 4 });
        }
      }

      // 4) 地上の歩行者目線へ
      await gate();
      let onGround = await toGround(start.p, start.look);
      caption(onGround ? '歩行者目線に切り替えました' : '');
      await pause(1200);

      // 5) 店を順に巡る
      for (let i = 0; i < S.order.length; i++) {
        const store = S.order[i];
        caption(`${i + 1} 軒目「${store.name}」へ移動中`);
        if (onGround) {
          const remain = await S.ground.walkTo(store.pos, S.path, gate);
          if (remain > 60) flash('ストリートビューの道がここで途切れたため、店舗の手前で停止しました。');
        } else if (S.aerial) {
          const from = i ? S.order[i - 1].pos : start.p;
          await fly(store.pos, { heading: bearing(from, store.pos) || 0, pitch: -30, range: S.aerialKind === '3d' && S.aerial.groundH == null ? 320 : 110, duration: 4 });
        }
        await gate();
        caption(`${i + 1} 軒目「${store.name}」`);
        await openPanel(store);
        // 「次へ」が押されるまで待つ
        await new Promise((res, rej) => { t.waitNext = { res, rej }; tourButtons(); });
        t.waitNext = null; tourButtons(); closePanel();
        if (!onGround && S.ground) onGround = await toGround(store.pos, S.order[i + 1]?.pos); // 途中から地上に降りられる場合
      }
      caption('おつかれさまでした。飲み歩き完了！');
      await sleep(2500);
    } catch (e) {
      if (!(e instanceof Cancelled)) { console.error(e); flash('ツアー中にエラーが発生したため終了しました。'); }
    } finally {
      S.tour = null; tourButtons(); caption(''); setMode('free');
    }
  }
  function endTour() {
    const t = S.tour; if (!t) return;
    t.cancelled = true; t.paused = false;
    S.aerial?.cancel();
    t.waitNext?.rej(new Cancelled());
    closePanel();
  }

  // ---------- 周辺の実在店舗を Google から追加（任意） ----------
  async function addNearby() {
    if (!S.googleReady || S.path.length < 2) return flash('道順が取得できていないため、周辺店舗を検索できません。');
    try {
      const { Place } = await google.maps.importLibrary('places');
      const L = Path.length(S.path), mid = Path.at(S.path, L / 2);
      const { places } = await Place.searchNearby({
        fields: PLACE_FIELDS, language: 'ja', maxResultCount: 20,
        locationRestriction: { center: mid, radius: Math.min(500, L / 2 + 40) },
        includedPrimaryTypes: ['restaurant', 'bar', 'japanese_restaurant', 'izakaya_restaurant', 'pub', 'ramen_restaurant', 'cafe'],
      });
      let added = 0;
      for (const p of places || []) {
        if (!p.location || p.businessStatus !== 'OPERATIONAL') continue;
        const pos = lit(p.location);
        if (Path.project(S.path, pos).d > 15) continue; // 道順から 15 m 以内だけ
        if (S.stores.some((s) => s.place?.id === p.id)) continue;
        S.stores.push({ id: 'g_' + p.id, name: p.displayName, match: p.displayName, address: p.formattedAddress, features: [],
          sources: [], auto: true, place: p, pos, resolved: true, error: null,
          note: 'Google マップから自動取得した店舗です（道順から 15 m 以内）。サンシティ通りの店舗かどうかは個別に確認していません。' });
        added++;
      }
      S.order = S.stores.filter((s) => s.resolved).sort((a, b) => Path.project(S.path, a.pos).s - Path.project(S.path, b.pos).s);
      refreshMarkers(); renderList();
      flash(added ? `Google マップから ${added} 軒を追加しました（自動取得・要確認）。` : '道順沿いに追加できる店舗は見つかりませんでした。');
    } catch (e) { console.warn(e); flash('周辺店舗を取得できませんでした（Places API (New) を確認してください）。'); }
  }

  // ---------- 起動 ----------
  async function boot() {
    renderList();
    if (!S.key) { setStatus('API キー未設定：地図は表示されません。店舗リストは「店舗」から見られます。'); $('keyDialog').showModal(); return; }
    setStatus('読み込み中…');

    // Google Maps JS（ストリートビュー・Places・フォールバック地図）
    try { await loadGoogle(S.key); S.googleReady = true; }
    catch (e) { console.warn(e); }

    // 上空: まず Photorealistic 3D Tiles、だめなら通常の地図
    try {
      const a = await CesiumAerial.create($('aerial'), S.key);
      const got = await withTimeout(a.firstTile, 15000, false);
      if (!got) { a.destroy(); throw new Error('3D タイルが届きません'); }
      S.aerial = a; S.aerialKind = '3d';
      a.fly(DATA.overview, { heading: 0, pitch: -90, range: 9000, duration: 0 });
    } catch (e) {
      console.warn('[KNW] 3D tiles unavailable, falling back to 2D map', e);
      $('aerial').innerHTML = '';
      if (S.googleReady) {
        try { S.aerial = await MapAerial.create($('aerial')); S.aerialKind = '2d'; } catch (e2) { console.warn(e2); }
      }
    }
    if (S.aerial) S.aerial.onStoreClick = (id) => { const s = S.stores.find((x) => x.id === id); if (s) openPanel(s, { visit: S.mode === 'free' }); };

    if (S.googleReady) {
      try {
        S.ground = await Ground.create($('ground'), $('minimap'));
        S.ground.onMove = (p) => { S.aerial?.setCurrent(p); nextStoreInfo(p); };
        S.ground.onStoreClick = (id) => { const s = S.stores.find((x) => x.id === id); if (s) openPanel(s); };
      } catch (e) { console.warn('[KNW] street view init failed', e); }
      await Promise.all([...S.stores.map(resolveStore), resolveEntrance()]);
      decideOrder();
      await buildPath();
    }
    if (S.aerial && S.order.length) {
      const h = await S.aerial.sampleGround(S.order[0].pos);
      if (h != null) S.aerial.groundH = h;
    }
    S.aerial?.setPath(S.path); S.ground?.setPath(S.path);
    refreshMarkers(); renderList();

    const notes = [];
    if (!S.aerial) notes.push('地図を表示できませんでした（API キー・有効化 API を確認）');
    else if (S.aerialKind === '2d') notes.push('3D データを利用できないため通常の地図で表示しています');
    const missing = S.stores.filter((s) => !s.resolved).length;
    if (missing) notes.push(`${missing} 軒は位置を確認できず、地図に表示していません`);
    if (S.order.length && S.pathApprox) notes.push('道順を取得できなかったため、線は店舗間を結ぶ概略です');
    if (notes.length) flash(notes.join(' ／ '), 12000); else setStatus('');

    // フリーモードの初期視点: 通り全体が見える高さへ
    if (S.aerial && S.order.length && !S.tour) {
      const mid = Path.at(S.path, Path.length(S.path) / 2);
      S.aerial.fly(mid, { heading: 0, pitch: -50, range: 700, duration: 4 });
    }
  }

  // ---------- イベント ----------
  $('modeFree').onclick = () => { if (S.tour) endTour(); setMode('free'); };
  $('modeTour').onclick = () => setMode('tour');
  $('btnStart').onclick = startTour;
  $('btnPause').onclick = () => { if (S.tour) { S.tour.paused = true; S.aerial?.cancel(); tourButtons(); caption('一時停止中'); } };
  $('btnResume').onclick = () => { if (S.tour) { S.tour.paused = false; tourButtons(); caption(''); } };
  $('btnNext').onclick = () => S.tour?.waitNext?.res();
  $('btnEnd').onclick = endTour;
  $('btnWalk').onclick = () => { const g = groundStart(); walkFree(g?.p, g?.look); };
  $('btnSky').onclick = toAerial;
  $('btnNearby').onclick = addNearby;
  $('btnNight').onclick = () => { const on = document.body.classList.toggle('night'); $('btnNight').setAttribute('aria-pressed', on); };
  $('btnList').onclick = () => { $('list').hidden = !$('list').hidden; if (!$('list').hidden) $('panel').hidden = true; };
  $('listClose').onclick = () => { $('list').hidden = true; };
  $('panelClose').onclick = () => { if (S.tour?.waitNext) S.tour.waitNext.res(); else closePanel(); };
  $('btnReset').onclick = () => { S.visited.clear(); localStorage.removeItem(LS_VISITED); refreshMarkers(); renderList(); };
  const pickFromList = (e) => {
    const li = e.target.closest('li[data-id]'); if (!li) return;
    const s = S.stores.find((x) => x.id === li.dataset.id); if (!s) return;
    openPanel(s, { visit: false });
    if (s.resolved && S.view === 'aerial' && S.aerial && !S.tour) S.aerial.fly(s.pos, { heading: 0, pitch: -40, range: 180, duration: 2.5 });
  };
  $('listBody').addEventListener('click', pickFromList);
  $('listBody').addEventListener('keydown', (e) => { if (e.key === 'Enter') pickFromList(e); });
  $('btnKey').onclick = () => { $('keyInput').value = S.key; $('keyDialog').showModal(); };
  $('keyCancel').onclick = () => $('keyDialog').close();
  $('keyClear').onclick = () => { localStorage.removeItem(LS_KEY); location.href = location.pathname; };
  $('keyForm').addEventListener('submit', () => {
    const k = $('keyInput').value.trim();
    if (!k) return;
    localStorage.setItem(LS_KEY, k);
    location.href = location.pathname; // キーを反映して再読み込み
  });

  window.KNW = { S, Path, dist, bearing }; // デバッグ・テスト用
  boot().catch((e) => { console.error(e); setStatus('起動中にエラーが発生しました。'); });
})();

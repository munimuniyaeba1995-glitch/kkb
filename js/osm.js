/* OpenStreetMap（Overpass API）から、サンシティ通りの線と沿道の飲食店を取得する。
 * データ © OpenStreetMap contributors（ODbL）。API キー不要。
 * 取得できないものは空のまま返す（架空データで補わない）。
 */
window.KNW_OSM = (() => {
  'use strict';
  const CFG = window.KNW_CONFIG;
  const { dist, Path } = window.KNW_GEO;
  const CACHE_KEY = 'knw.osm.v2';

  async function overpass(query) {
    let lastErr;
    for (const url of CFG.overpassEndpoints) {
      const ctl = new AbortController();
      const timer = setTimeout(() => ctl.abort(), 30000);
      try {
        const res = await fetch(url, { method: 'POST', body: new URLSearchParams({ data: query }), signal: ctl.signal });
        if (!res.ok) throw new Error(`Overpass ${res.status}`);
        return await res.json();
      } catch (e) { lastErr = e; } finally { clearTimeout(timer); }
    }
    throw lastErr || new Error('Overpass に接続できません');
  }

  const centerOf = (el) => {
    if (el.lat != null) return { lat: el.lat, lng: el.lon };
    if (el.center) return { lat: el.center.lat, lng: el.center.lon };
    if (el.bounds) return { lat: (el.bounds.minlat + el.bounds.maxlat) / 2, lng: (el.bounds.minlon + el.bounds.maxlon) / 2 };
    if (el.geometry?.length) {
      const g = el.geometry.filter(Boolean);
      return { lat: g.reduce((a, p) => a + p.lat, 0) / g.length, lng: g.reduce((a, p) => a + p.lon, 0) / g.length };
    }
    return null;
  };

  /** 端点が一致する way をつないで、いちばん長い 1 本の線にする */
  function chainWays(ways) {
    const segs = ways.map((w) => w.geometry.map((p) => ({ lat: p.lat, lng: p.lon }))).filter((g) => g.length >= 2);
    const same = (a, b) => Math.abs(a.lat - b.lat) < 1e-7 && Math.abs(a.lng - b.lng) < 1e-7;
    const chains = [];
    while (segs.length) {
      let chain = segs.shift(), grew = true;
      while (grew) {
        grew = false;
        for (let i = 0; i < segs.length; i++) {
          const g = segs[i], head = chain[0], tail = chain[chain.length - 1];
          let next = null;
          if (same(tail, g[0])) next = chain.concat(g.slice(1));
          else if (same(tail, g[g.length - 1])) next = chain.concat(g.slice(0, -1).reverse());
          else if (same(head, g[g.length - 1])) next = g.slice(0, -1).concat(chain);
          else if (same(head, g[0])) next = g.slice(1).reverse().concat(chain);
          if (next) { chain = next; segs.splice(i, 1); grew = true; break; }
        }
      }
      chains.push(chain);
    }
    chains.sort((a, b) => Path.length(b) - Path.length(a));
    return chains[0] || [];
  }

  function toStore(el) {
    const pos = centerOf(el);
    const t = el.tags || {};
    if (!pos) return null;
    return { id: `${el.type}/${el.id}`, osmType: el.type, osmId: el.id, pos, tags: t, name: t.name || t['name:ja'] || t['name:en'] || null };
  }

  /**
   * 返り値:
   *  { street: [{lat,lng}], streetName, streetSource: 'way' | 'feature' | null,
   *    feature: {name, pos} | null, stores: [...], fetchedAt, fromCache }
   */
  async function load({ force = false } = {}) {
    if (!force) {
      try {
        const c = JSON.parse(localStorage.getItem(CACHE_KEY) || 'null');
        if (c && Date.now() - c.fetchedAt < CFG.cacheHours * 3600e3) return { ...c, fromCache: true };
      } catch { /* キャッシュが壊れていたら取り直す */ }
    }
    const { lat, lng } = CFG.center;
    // 1) 「サンシティ」という名前の地物（道路・商店街など）を探す
    const named = await overpass(`[out:json][timeout:25];
nwr(around:${CFG.searchRadius},${lat},${lng})["name"~"${CFG.streetNamePattern}",i];
out geom tags;`);
    const els = named.elements || [];
    const ways = els.filter((e) => e.type === 'way' && e.tags?.highway && e.geometry?.length >= 2);
    const out = { street: [], streetName: null, streetSource: null, feature: null, stores: [], fetchedAt: Date.now() };

    let around = null;
    if (ways.length) {
      out.street = chainWays(ways);
      out.streetName = ways[0].tags.name;
      out.streetSource = 'way';
      const coords = out.street.map((p) => `${p.lat.toFixed(7)},${p.lng.toFixed(7)}`).join(',');
      around = `around:${CFG.poiRadiusStreet},${coords}`;
    } else {
      // 道路としては未登録。名前付き地物（商店街の POI など）があれば、その周辺で探す
      const feats = els.map((e) => ({ name: e.tags?.name, pos: centerOf(e) })).filter((f) => f.pos)
        .sort((a, b) => dist(a.pos, CFG.center) - dist(b.pos, CFG.center));
      if (feats.length) {
        out.feature = feats[0];
        out.streetSource = 'feature';
        around = `around:${CFG.poiRadiusFeature},${feats[0].pos.lat},${feats[0].pos.lng}`;
      }
    }

    // 2) 沿道の飲食店
    if (around) {
      const pois = await overpass(`[out:json][timeout:25];
nwr(${around})["amenity"~"^(${CFG.amenities.join('|')})$"];
out center tags;`);
      out.stores = (pois.elements || []).map(toStore).filter(Boolean);
    }
    try { localStorage.setItem(CACHE_KEY, JSON.stringify(out)); } catch { /* 保存できなくても続行 */ }
    return { ...out, fromCache: false };
  }

  return { load, chainWays };
})();

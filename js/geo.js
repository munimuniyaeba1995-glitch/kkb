/* 地理計算の小道具（地図ライブラリに依存しない） */
window.KNW_GEO = (() => {
  'use strict';
  const R = 6371008.8;
  const rad = (d) => (d * Math.PI) / 180;
  const deg = (r) => (r * 180) / Math.PI;

  /** 2 点間距離 (m) */
  function dist(a, b) {
    const dLat = rad(b.lat - a.lat), dLng = rad(b.lng - a.lng);
    const h = Math.sin(dLat / 2) ** 2 + Math.cos(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.sin(dLng / 2) ** 2;
    return 2 * R * Math.asin(Math.sqrt(h));
  }
  /** a から b への方位（度、北 = 0、時計回り） */
  function bearing(a, b) {
    const y = Math.sin(rad(b.lng - a.lng)) * Math.cos(rad(b.lat));
    const x = Math.cos(rad(a.lat)) * Math.sin(rad(b.lat)) - Math.sin(rad(a.lat)) * Math.cos(rad(b.lat)) * Math.cos(rad(b.lng - a.lng));
    return (deg(Math.atan2(y, x)) + 360) % 360;
  }
  const signedDiff = (from, to) => ((to - from + 540) % 360) - 180;
  const xy = (p, o) => ({ x: rad(p.lng - o.lng) * R * Math.cos(rad(o.lat)), y: rad(p.lat - o.lat) * R });

  const Path = {
    length(path) { let L = 0; for (let i = 0; i < path.length - 1; i++) L += dist(path[i], path[i + 1]); return L; },
    /** 点 p を線に射影: { s: 起点からの道のり, d: 線までの距離 } (m) */
    project(path, p) {
      if (path.length === 1) return { s: 0, d: dist(path[0], p) };
      let best = { s: 0, d: Infinity }, acc = 0;
      for (let i = 0; i < path.length - 1; i++) {
        const o = path[i], b = xy(path[i + 1], o), q = xy(p, o);
        const len2 = b.x * b.x + b.y * b.y, len = Math.sqrt(len2);
        const t = len2 ? Math.max(0, Math.min(1, (q.x * b.x + q.y * b.y) / len2)) : 0;
        const d = Math.hypot(q.x - t * b.x, q.y - t * b.y);
        if (d < best.d) best = { s: acc + t * len, d };
        acc += len;
      }
      return best;
    },
    /** 起点から道のり s の地点と、その場所での進行方位 */
    at(path, s) {
      if (path.length === 1) return { ...path[0], bearing: 0 };
      let acc = 0;
      for (let i = 0; i < path.length - 1; i++) {
        const len = dist(path[i], path[i + 1]);
        if (len > 0 && (acc + len >= s || i === path.length - 2)) {
          const t = Math.max(0, Math.min(1, (s - acc) / len));
          return {
            lat: path[i].lat + (path[i + 1].lat - path[i].lat) * t,
            lng: path[i].lng + (path[i + 1].lng - path[i].lng) * t,
            bearing: bearing(path[i], path[i + 1]),
          };
        }
        acc += len;
      }
      return { ...path[path.length - 1], bearing: 0 };
    },
  };
  return { dist, bearing, signedDiff, Path };
})();

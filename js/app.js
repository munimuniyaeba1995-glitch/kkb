/* KOZA NIGHT WALK — アプリ本体（API キー不要版）
 *
 * 地図は window.KNW_createMap が返すアダプター越しにだけ操作する（js/map-maplibre.js 参照）。
 * 実データ: OpenStreetMap の道路・建物・店舗 ／ 演出: カメラワーク、夜景フィルター、UI
 */
(() => {
  'use strict';
  const CFG = window.KNW_CONFIG;
  const { dist, bearing, signedDiff, Path } = window.KNW_GEO;
  const $ = (id) => document.getElementById(id);
  const LS_VISITED = 'knw.visited.osm';
  const sleep = (ms) => new Promise((r) => setTimeout(r, ms));
  const frame = () => new Promise((r) => requestAnimationFrame(r));
  const esc = (s) => String(s ?? '').replace(/[&<>"']/g, (c) => ({ '&': '&amp;', '<': '&lt;', '>': '&gt;', '"': '&quot;', "'": '&#39;' }[c]));

  const WALK = { zoom: 19.4, pitch: 72, speed: 7 };  // 歩行ビュー（演出値）。speed は m/秒
  const AMENITY = { restaurant: 'レストラン・食堂', bar: 'バー', pub: '居酒屋・パブ', cafe: 'カフェ', fast_food: 'ファストフード',
    biergarten: 'ビアガーデン', nightclub: 'ナイトクラブ', food_court: 'フードコート', ice_cream: 'アイスクリーム' };

  const S = {
    map: null,
    osm: null,            // KNW_OSM.load() の結果。取得失敗なら null
    order: [],            // 巡る順に並べた店舗（位置あり）
    extras: [],           // OSM に無いが公開情報で確認できた店（位置なし）
    path: [],             // 歩く線。OSM の道路、無ければ店舗間を結ぶ概略線
    pathIsStreet: false,
    mode: 'free', view: 'aerial',
    walkS: 0, walkDir: 0,
    visited: new Set(JSON.parse(localStorage.getItem(LS_VISITED) || '[]')),
    tour: null, openStore: null,
  };

  // ---------- UI 基本 ----------
  let statusTimer;
  function setStatus(msg) { const el = $('status'); el.textContent = msg || ''; el.hidden = !msg; }
  function flash(msg, ms = 6000) { setStatus(msg); clearTimeout(statusTimer); statusTimer = setTimeout(() => setStatus(''), ms); }
  const caption = (t) => { $('caption').textContent = t || ''; };
  function setMode(mode) {
    S.mode = mode;
    document.body.classList.toggle('mode-free', mode === 'free');
    document.body.classList.toggle('mode-tour', mode === 'tour');
    $('modeFree').setAttribute('aria-selected', mode === 'free');
    $('modeTour').setAttribute('aria-selected', mode === 'tour');
    caption(mode === 'tour' && !S.tour ? 'スタートで上空からサンシティ通りへ' : '');
  }
  function setView(view) {
    S.view = view;
    document.body.classList.toggle('view-aerial', view === 'aerial');
    document.body.classList.toggle('view-walk', view === 'walk');
    if (view === 'aerial') { $('where').textContent = ''; S.map.setCurrent(null); }
  }
  const storeName = (s) => s.name || '（名称未登録の飲食店）';
  function markVisited(s) {
    if (!s.pos || S.visited.has(s.id)) return;
    S.visited.add(s.id);
    localStorage.setItem(LS_VISITED, JSON.stringify([...S.visited]));
    S.map.setStores(S.order, S.visited); renderList();
  }

  // ---------- データの組み立て ----------
  function buildStores() {
    const osm = S.osm;
    const stores = (osm?.stores || []).map((s) => ({ ...s, note: s.name ? CFG.notes.find((n) => s.name.includes(n.match)) || null : null }));
    S.extras = CFG.notes.filter((n) => !stores.some((s) => s.note === n));
    if (osm?.street?.length >= 2) {
      S.path = osm.street.slice(); S.pathIsStreet = true;
      // 胡屋十字路（初期表示の中心）に近い端を起点にする
      if (dist(CFG.center, S.path[S.path.length - 1]) < dist(CFG.center, S.path[0])) S.path.reverse();
      stores.forEach((s) => { s.s = Path.project(S.path, s.pos).s; });
      S.order = stores.sort((a, b) => a.s - b.s);
    } else {
      // 道路の線が無い: 近い順につないだ概略線（実際の道ではない、と画面に出す）
      const rest = stores.slice().sort((a, b) => a.pos.lng - b.pos.lng), order = [];
      let cur = rest.shift();
      while (cur) { order.push(cur); rest.sort((a, b) => dist(cur.pos, a.pos) - dist(cur.pos, b.pos)); cur = rest.shift(); }
      S.order = order; S.path = order.map((s) => s.pos); S.pathIsStreet = false;
      order.forEach((s) => { s.s = Path.project(S.path, s.pos).s; });
    }
  }

  // ---------- 店舗パネル ----------
  const osmLink = (s) => `https://www.openstreetmap.org/${s.osmType}/${s.osmId}`;
  function addressOf(t) {
    if (t['addr:full']) return t['addr:full'];
    const parts = ['addr:province', 'addr:city', 'addr:quarter', 'addr:neighbourhood', 'addr:block_number', 'addr:housenumber'].map((k) => t[k]).filter(Boolean);
    return parts.length ? parts.join(' ') : null;
  }
  const safeUrl = (u) => (/^https?:\/\//i.test(u || '') ? u : null);
  function row(label, value, html = false) {
    return `<dt>${label}</dt><dd>${value ? (html ? value : esc(value)) : '<span class="none">OSM に登録なし</span>'}</dd>`;
  }
  function openPanel(s, { visit = true } = {}) {
    S.openStore = s;
    if (visit) markVisited(s);
    const t = s.tags || {}, note = s.note || (s.pos ? null : s);
    const web = safeUrl(t.website || t['contact:website']);
    const img = safeUrl(t.image);
    const badges = [];
    if (s.pos) badges.push('<span class="badge ok">位置: OpenStreetMap</span>'); else badges.push('<span class="badge warn">位置: 未確認（地図に表示していません）</span>');
    if (S.visited.has(s.id)) badges.push('<span class="badge visit">訪問済み ✓</span>');
    const feats = note?.features || [];
    const srcs = (note?.sources || []).map((x) => `<a href="${esc(x.url)}" target="_blank" rel="noopener">${esc(x.label)}</a>`).join(' / ');
    const q = encodeURIComponent(`${s.name || ''} 沖縄市中央`);
    $('panelBody').innerHTML = `
      <h2>${esc(storeName(s))}</h2>
      <div class="badges">${badges.join('')}</div>
      ${s.pos ? `<h3>基本情報（OpenStreetMap）</h3>
      <dl class="info">
        ${row('種別', AMENITY[t.amenity] || t.amenity)}
        ${row('料理', t.cuisine?.replace(/;/g, '、').replace(/_/g, ' '))}
        ${row('営業時間', t.opening_hours)}
        ${row('住所', addressOf(t) || note?.address)}
        ${row('電話', t.phone || t['contact:phone'])}
        ${row('Web', web && `<a href="${esc(web)}" target="_blank" rel="noopener">${esc(web)}</a>`, true)}
        ${t.level ? row('階', t.level) : ''}
        ${t.check_date ? row('確認日', t.check_date) : ''}
      </dl>
      <p class="fine">営業時間は OSM の書式のまま表示しています（例: Mo-Sa 18:00-24:00）。ボランティアが登録した情報のため、来店前に店舗へご確認ください。</p>
      <h3>写真</h3>
      ${img ? `<div class="photos"><figure><img loading="lazy" src="${esc(img)}" alt="${esc(storeName(s))}"><figcaption>OSM の image タグより</figcaption></figure></div>`
        : '<p class="unknown">OSM に写真の登録がありません。架空の画像は表示していません。</p>'}`
        : `<p>${note?.address ? esc(note.address) : '<span class="unknown">住所は確認できませんでした</span>'}</p>
      <p class="unknown">この店は OpenStreetMap に見つからなかったため、位置・営業時間は表示していません。</p>`}
      ${feats.length ? `<h3>店舗の特徴（公開情報）</h3><ul class="features">${feats.map((f) => `<li>${esc(f)}</li>`).join('')}</ul>` : ''}
      ${srcs ? `<p class="fine">出典: ${srcs}</p>` : ''}
      <div class="actions">
        ${s.pos ? `<a class="btn" href="${esc(osmLink(s))}" target="_blank" rel="noopener">OpenStreetMap で見る</a>` : ''}
        ${s.name ? `<a class="btn" href="https://www.google.com/maps/search/?api=1&query=${q}" target="_blank" rel="noopener">Google マップで検索</a>` : ''}
        ${s.pos && S.mode === 'free' ? '<button id="panelGo">ここへ行く</button>' : ''}
      </div>`;
    $('panel').hidden = false; $('list').hidden = true;
    $('panelGo')?.addEventListener('click', () => { closePanel(); enterWalk(s.s, s); });
  }
  function closePanel() { $('panel').hidden = true; S.openStore = null; }

  function renderList() {
    const o = S.osm;
    $('listNote').textContent = !o ? '店舗データ（OpenStreetMap）を取得できませんでした。'
      : S.order.length ? `OpenStreetMap に登録されている飲食店 ${S.order.length} 件（${new Date(o.fetchedAt).toLocaleDateString('ja-JP')} 取得）。`
      : '条件に合う飲食店は OpenStreetMap に見つかりませんでした。';
    $('listBody').innerHTML = S.order.map((s) => `
      <li data-id="${esc(s.id)}" class="${S.visited.has(s.id) ? 'visited' : ''}" tabindex="0">
        <b>${esc(storeName(s))}</b>${S.visited.has(s.id) ? ' <span class="badge visit">訪問済み</span>' : ''}
        <small>${esc(AMENITY[s.tags.amenity] || s.tags.amenity || '')}${s.tags.opening_hours ? ' ・ ' + esc(s.tags.opening_hours) : ''}</small>
      </li>`).join('');
    $('extraBox').hidden = !S.extras.length;
    $('extraBody').innerHTML = S.extras.map((n, i) => `<li><a href="#" data-extra="${i}">${esc(n.name)}</a></li>`).join('');
  }

  // ---------- 歩行ビュー（道路に沿って移動するカメラ） ----------
  let lastBearing = null;
  function placeWalkCamera(s, { instant = false } = {}) {
    const L = Path.length(S.path);
    S.walkS = Math.max(0, Math.min(L, s));
    const p = Path.at(S.path, S.walkS);
    const target = S.walkDir < 0 ? (p.bearing + 180) % 360 : p.bearing;
    lastBearing = instant || lastBearing == null ? target : lastBearing + signedDiff(lastBearing, target) * 0.07;
    S.map.setCamera({ center: p, zoom: WALK.zoom, pitch: WALK.pitch, bearing: lastBearing });
    S.map.setCurrent(p);
    updateWhere(p);
    return p;
  }
  function updateWhere(p) {
    const next = S.order.find((x) => !S.visited.has(x.id));
    $('where').textContent = `${S.pathIsStreet ? '通りの起点から' : '概略線の起点から'} 約 ${Math.round(S.walkS)} m`
      + (next ? ` ・ 次の未訪問店「${storeName(next)}」まで約 ${Math.round(dist(p, next.pos))} m` : S.order.length ? ' ・ 全店訪問済み' : '');
    // フリー歩行中に店の前を通ったら訪問済みにする
    if (!S.tour) for (const x of S.order) if (!S.visited.has(x.id) && Math.abs(x.s - S.walkS) < 6) { markVisited(x); caption(`「${storeName(x)}」の前です`); }
  }
  /** 上空 → 歩行ビューへ降りる */
  async function enterWalk(s = 0, lookAtStore = null) {
    if (S.path.length < 2 && !S.order.length) return flash('通りの道路データを取得できていないため、歩行ビューを開始できません。');
    const L = Path.length(S.path); s = Math.max(0, Math.min(L, s));
    const p = Path.at(S.path, s);
    S.walkDir = 0; lastBearing = lookAtStore && dist(p, lookAtStore.pos) > 1 ? bearing(p, lookAtStore.pos) : p.bearing;
    await S.map.flyTo({ center: p, zoom: WALK.zoom, pitch: WALK.pitch, bearing: lastBearing, duration: 2.5 });
    setView('walk'); S.walkS = s; S.map.setCurrent(p); updateWhere(p);
  }
  async function toAerial() {
    S.walkDir = 0;
    const mid = S.path.length ? Path.at(S.path, Path.length(S.path) / 2) : CFG.center;
    setView('aerial');
    await S.map.flyTo({ center: mid, zoom: 17, pitch: 50, bearing: 0, duration: 2.5 });
  }
  /** フリー歩行: ボタンやキーを押している間、道に沿って進む／戻る */
  async function freeWalkLoop() {
    let prev = performance.now();
    for (;;) {
      const now = await frame(); const dt = Math.min(0.1, (now - prev) / 1000); prev = now;
      if (S.walkDir && S.view === 'walk' && !S.tour && S.path.length >= 2) placeWalkCamera(S.walkS + S.walkDir * WALK.speed * dt);
    }
  }

  // ---------- 自動ツアー ----------
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
    const stops = S.order.length ? S.order : S.extras.map((n, i) => ({ ...n, id: 'note' + i, pos: null }));
    if (!stops.length) return flash('紹介できる店舗データがありません。');
    const t = S.tour = { paused: false, waitNext: null, cancelled: false };
    const gate = async () => { while (t.paused && !t.cancelled) await sleep(100); if (t.cancelled) throw new Cancelled(); };
    const pause = async (ms) => { const end = Date.now() + ms; while (Date.now() < end) { await gate(); await sleep(60); } };
    const fly = async (cam) => { for (;;) { await gate(); if (await S.map.flyTo(cam)) return; await sleep(40); } };
    const walkTo = async (sTo) => {
      S.walkDir = sTo >= S.walkS ? 1 : -1;
      let prev = performance.now();
      while (Math.abs(sTo - S.walkS) > 0.3) {
        const now = await frame(); const dt = Math.min(0.1, (now - prev) / 1000); prev = now;
        await gate();
        const step = Math.min(Math.abs(sTo - S.walkS), WALK.speed * dt);
        placeWalkCamera(S.walkS + S.walkDir * step);
      }
    };
    const turnTo = async (target) => {
      const from = lastBearing ?? target, d = signedDiff(from, target), n = Math.max(1, Math.round(Math.abs(d) / 2.5));
      for (let i = 1; i <= n; i++) { await gate(); const e = i / n; lastBearing = from + d * (e < 0.5 ? 2 * e * e : 1 - (-2 * e + 2) ** 2 / 2); S.map.setCamera({ bearing: lastBearing }); await frame(); }
    };
    tourButtons(); closePanel();
    try {
      const hasGeo = S.order.length > 0 && S.map.kind !== 'none';
      if (hasGeo) {
        const start = Path.at(S.path, 0);
        setView('aerial');
        // 1) コザ上空 → 2) 降下 → 3) 通りの起点へ（ドローン風の演出）
        caption('沖縄市コザ 上空');
        S.map.setCamera({ center: CFG.center, zoom: 11.5, pitch: 0, bearing: 0 });
        await pause(1500);
        caption('サンシティ通りへ降下中…');
        await fly({ center: start, zoom: 15, pitch: 35, bearing: start.bearing - 50, duration: 5 });
        await fly({ center: start, zoom: 17.6, pitch: 58, bearing: start.bearing - 15, duration: 4 });
        // 4) 歩行者に近い視点へ
        lastBearing = start.bearing;
        await fly({ center: start, zoom: WALK.zoom, pitch: WALK.pitch, bearing: start.bearing, duration: 3 });
        setView('walk'); S.walkS = 0; placeWalkCamera(0, { instant: true });
        caption(S.pathIsStreet ? '通りを歩きます' : '店舗間を移動します（概略線）');
        await pause(900);
      }
      // 5) 店を順に巡る
      for (let i = 0; i < stops.length; i++) {
        const s = stops[i];
        caption(`${i + 1} 軒目「${storeName(s)}」へ`);
        if (hasGeo) {
          await walkTo(s.s);
          const here = Path.at(S.path, S.walkS);
          if (dist(here, s.pos) > 1) await turnTo(bearing(here, s.pos)); // 店の方向を向く
        } else await pause(600);
        await gate();
        caption(`${i + 1} 軒目「${storeName(s)}」`);
        openPanel(s);
        await new Promise((res, rej) => { t.waitNext = { res, rej }; tourButtons(); });
        t.waitNext = null; tourButtons(); closePanel();
      }
      caption('おつかれさまでした。飲み歩き完了！');
      await sleep(2200);
    } catch (e) {
      if (!(e instanceof Cancelled)) { console.error(e); flash('ツアー中にエラーが発生したため終了しました。'); }
    } finally {
      S.tour = null; S.walkDir = 0; tourButtons(); setMode('free');
    }
  }
  function endTour() {
    const t = S.tour; if (!t) return;
    t.cancelled = true; t.paused = false; S.map.stop(); t.waitNext?.rej(new Cancelled()); closePanel();
  }

  // ---------- 起動 ----------
  async function loadData(force) {
    try { S.osm = await window.KNW_OSM.load({ force }); }
    catch (e) { console.warn('[KNW] overpass failed', e); S.osm = null; }
    buildStores();
    S.map.setStreet(S.path); S.map.setStores(S.order, S.visited); renderList();
  }
  function report() {
    const n = [], o = S.osm, k = S.map.kind;
    if (k === 'none') n.push('地図を表示できないためデモ画面を表示しています');
    else if (k === 'blank') n.push('地図タイルを取得できませんでした。道路の線と店舗だけを表示しています');
    else if (k === 'raster') n.push('3D 建物に対応した地図を取得できなかったため、通常の地図（OSM 標準タイル）で表示しています');
    if (!o) n.push('店舗データ（Overpass API）を取得できませんでした。時間をおいて「店舗データを取り直す」をお試しください');
    else if (!o.streetSource) n.push('OpenStreetMap に「サンシティ」という名前の道路・施設が見つからなかったため、店舗マーカーは表示していません');
    else if (o.streetSource === 'feature') n.push(`OpenStreetMap に同名の道路は無く、「${o.feature.name}」の周辺 ${CFG.poiRadiusFeature} m の飲食店を表示しています。線は店舗間を結ぶ概略です`);
    else if (!S.order.length) n.push('通り沿いに OpenStreetMap 登録の飲食店が見つかりませんでした');
    if (n.length) flash(n.join(' ／ '), 14000); else setStatus('');
  }
  async function boot() {
    setStatus('読み込み中…');
    S.map = await window.KNW_createMap($('map'), CFG);
    $('demo').hidden = S.map.kind !== 'none';
    $('map').hidden = S.map.kind === 'none';
    $('credit').innerHTML = `地図データ ${S.map.attribution}`;
    document.body.classList.toggle('style-light', S.map.kind === 'raster' || S.map.styleId === 'liberty');
    $('btn3D').hidden = !S.map.has3D;
    S.map.onStoreClick = (id) => { const s = S.order.find((x) => x.id === id); if (s) openPanel(s, { visit: S.mode === 'free' }); };
    await loadData(false);
    report();
    freeWalkLoop();
    if (S.path.length && !S.tour) {
      const mid = Path.at(S.path, Path.length(S.path) / 2);
      S.map.flyTo({ center: mid, zoom: 17, pitch: 50, bearing: 0, duration: 3.5 });
    } else if (!S.tour) S.map.flyTo({ center: CFG.center, zoom: 15.5, pitch: 40, bearing: 0, duration: 3 });
  }

  // ---------- イベント ----------
  $('modeFree').onclick = () => { if (S.tour) endTour(); setMode('free'); };
  $('modeTour').onclick = () => setMode('tour');
  $('btnStart').onclick = startTour;
  $('btnPause').onclick = () => { if (S.tour) { S.tour.paused = true; S.map.stop(); tourButtons(); caption('一時停止中'); } };
  $('btnResume').onclick = () => { if (S.tour) { S.tour.paused = false; tourButtons(); caption(''); } };
  $('btnNext').onclick = () => S.tour?.waitNext?.res();
  $('btnEnd').onclick = endTour;
  $('btnWalk').onclick = () => enterWalk(0);
  $('btnSky').onclick = toAerial;
  const hold = (el, dir) => {
    const on = (e) => { e.preventDefault(); S.walkDir = dir; }, off = () => { if (S.walkDir === dir) S.walkDir = 0; };
    el.addEventListener('pointerdown', on); for (const ev of ['pointerup', 'pointerleave', 'pointercancel']) el.addEventListener(ev, off);
    el.addEventListener('contextmenu', (e) => e.preventDefault());
  };
  hold($('btnFwd'), 1); hold($('btnBack'), -1);
  addEventListener('keydown', (e) => { if (S.view !== 'walk' || S.tour) return; if (e.key === 'ArrowUp') S.walkDir = 1; else if (e.key === 'ArrowDown') S.walkDir = -1; else return; e.preventDefault(); });
  addEventListener('keyup', (e) => { if (e.key === 'ArrowUp' || e.key === 'ArrowDown') S.walkDir = 0; });
  $('btnNight').onclick = () => { const on = document.body.classList.toggle('night'); $('btnNight').setAttribute('aria-pressed', on); };
  $('btn3D').onclick = () => { const on = $('btn3D').getAttribute('aria-pressed') !== 'true'; $('btn3D').setAttribute('aria-pressed', on); S.map.set3D(on); };
  $('btnList').onclick = () => { $('list').hidden = !$('list').hidden; if (!$('list').hidden) $('panel').hidden = true; };
  $('listClose').onclick = () => { $('list').hidden = true; };
  $('panelClose').onclick = () => { if (S.tour?.waitNext) S.tour.waitNext.res(); else closePanel(); };
  $('btnReset').onclick = () => { S.visited.clear(); localStorage.removeItem(LS_VISITED); S.map.setStores(S.order, S.visited); renderList(); };
  $('btnReload').onclick = async () => { setStatus('店舗データを取得中…'); await loadData(true); report(); };
  const pick = (e) => {
    const li = e.target.closest('li[data-id]'); if (!li) return;
    const s = S.order.find((x) => x.id === li.dataset.id); if (!s) return;
    openPanel(s, { visit: false });
    if (S.view === 'aerial' && !S.tour) S.map.flyTo({ center: s.pos, zoom: 18.5, pitch: 55, bearing: S.map.getCamera().bearing, duration: 2 });
  };
  $('listBody').addEventListener('click', pick);
  $('listBody').addEventListener('keydown', (e) => { if (e.key === 'Enter') pick(e); });
  $('extraBody').addEventListener('click', (e) => {
    const a = e.target.closest('a[data-extra]'); if (!a) return;
    e.preventDefault(); const n = S.extras[+a.dataset.extra]; openPanel({ ...n, id: 'note', pos: null, tags: {} }, { visit: false });
  });

  window.KNW = { S }; // デバッグ・テスト用
  boot().catch((e) => { console.error(e); setStatus('起動中にエラーが発生しました。'); });
})();

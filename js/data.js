/*
 * KOZA NIGHT WALK — 設定と補足データ
 *
 * 方針
 *  - 店舗の位置・名称・営業時間などは、実行時に OpenStreetMap（Overpass API）から取得する。
 *  - ここには座標や営業時間を書かない。取得できない項目は画面に「登録なし」と出し、推測で埋めない。
 *  - notes は「公開情報で裏が取れた補足」だけ。OSM の店名に match が含まれる店に、出典付きで添える。
 */
window.KNW_CONFIG = {
  // 初期表示と検索の中心（コザ・胡屋十字路付近の目安）。店舗や道路の位置には使わない。
  center: { lat: 26.3341, lng: 127.8010 },
  searchRadius: 900,        // この半径内で「サンシティ」という名前の地物を OSM から探す (m)
  streetNamePattern: 'サンシティ|サンシテイ|Sun ?City',
  poiRadiusStreet: 25,      // 通りの線から何 m 以内の飲食店を対象にするか
  poiRadiusFeature: 120,    // 通りの線が特定できず、名前付き地物の周辺で探す場合の半径
  amenities: ['restaurant', 'bar', 'pub', 'cafe', 'fast_food', 'biergarten', 'nightclub', 'food_court', 'ice_cream'],
  overpassEndpoints: [
    'https://overpass-api.de/api/interpreter',
    'https://overpass.kumi.systems/api/interpreter',
  ],
  cacheHours: 24,           // Overpass の結果をブラウザに保存する時間（公共サーバーへの負荷を減らす）

  // 地図スタイル（すべて API キー不要）。上から順に試す。
  styles: [
    { id: 'dark', url: 'https://tiles.openfreemap.org/styles/dark' },
    { id: 'liberty', url: 'https://tiles.openfreemap.org/styles/liberty' },
  ],
  rasterTiles: 'https://tile.openstreetmap.org/{z}/{x}/{y}.png',

  notes: [
    {
      match: 'ロロイチ',
      name: '串揚げ肉団子と干物のお店 ロロイチ',
      address: '沖縄県沖縄市中央1-9-11',
      features: [
        '商店街「サンシティ」内にある創作居酒屋として紹介されている',
        '看板メニューは串揚げ肉団子。石川県能登半島直送の干物も提供',
      ],
      sources: [
        { label: 'ぐるなび', url: 'https://r.gnavi.co.jp/fbed701/' },
        { label: 'KOZA HOTELS ブログ', url: 'https://koza-hotels.org/2026/04/27/blog_01/' },
      ],
    },
    {
      match: 'なかた',
      name: '鉄板料理と和食の店 なかた',
      address: '沖縄県沖縄市中央1-13-6',
      features: ['サンシティ通りの商店街にある、泡盛にこだわった鉄板料理と和食の店として紹介されている'],
      sources: [
        { label: 'コザまちマガジン', url: 'https://kozamachi-magazine.com/kozanomimatome/' },
        { label: 'コザウェブ', url: 'https://www.kozaweb.jp/eats/10' },
      ],
    },
    {
      match: 'カキラバ',
      name: '牡蠣専門居酒屋 カキラバ',
      address: null, // 情報源により住所表記が食い違うため未記載
      features: ['コザウェブでエリア「サンシティ通り」の牡蠣専門居酒屋として掲載されている'],
      sources: [{ label: 'コザウェブ (EN)', url: 'https://en.kozaweb.jp/eats/show/366' }],
    },
  ],
};

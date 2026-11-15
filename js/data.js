/*
 * KOZA NIGHT WALK — 店舗シードデータ
 *
 * 方針（重要）
 *  - ここに書くのは「公開情報で裏が取れた事実」だけ。出典 URL を必ず付ける。
 *  - 緯度経度・営業時間・写真はここに書かない。実行時に Google Places から取得する。
 *    取得できなかった項目は画面に「確認できませんでした」と表示し、推測で埋めない。
 *  - 店を追加するときは stores 配列に同じ形で追記する（架空の店は入れない）。
 */
window.KNW_DATA = {
  // 演出用：オープニングで映す「沖縄市上空」の目安（沖縄市役所付近）。
  // ツアーの到着地点には使わない。到着地点は Places / Directions の実データから決まる。
  overview: { lat: 26.3344, lng: 127.8056 },

  // Places 検索の範囲を沖縄市中心部に寄せるためのバイアス（半径 m）
  biasRadius: 2500,
  // 取得した位置が overview からこの距離を超えたら別の店とみなして採用しない
  maxDistance: 3000,

  // 道順の起点に使う実在の交差点（Places で解決。解決できなければ 1 軒目から開始）
  entranceQuery: '胡屋十字路 沖縄市',

  stores: [
    {
      id: 'roroichi',
      name: '串揚げ肉団子と干物のお店 ロロイチ',
      match: 'ロロイチ',
      query: '串揚げ肉団子と干物のお店 ロロイチ 沖縄市中央',
      address: '沖縄県沖縄市中央1-9-11',
      features: [
        '商店街「サンシティ」内にある創作居酒屋として紹介されている',
        '看板メニューは串揚げ肉団子。石川県能登半島直送の干物も提供',
      ],
      sources: [
        { label: 'ぐるなび', url: 'https://r.gnavi.co.jp/fbed701/' },
        { label: 'KOZA HOTELS ブログ', url: 'https://koza-hotels.org/2026/04/27/blog_01/' },
      ],
      note: '営業時間はグルメサイト間で表記が食い違うため、ここでは固定せず Google マップの登録値を表示します。',
    },
    {
      id: 'nakata',
      name: '鉄板料理と和食の店 なかた',
      match: 'なかた',
      query: '鉄板料理と和食の店 なかた 沖縄市中央',
      address: '沖縄県沖縄市中央1-13-6',
      features: [
        'サンシティ通りの商店街にある、泡盛にこだわった鉄板料理と和食の店として紹介されている',
      ],
      sources: [
        { label: 'コザまちマガジン 飲みスポットまとめ', url: 'https://kozamachi-magazine.com/kozanomimatome/' },
        { label: 'コザウェブ 居酒屋・バー', url: 'https://www.kozaweb.jp/eats/10' },
      ],
      note: '公開記事の営業時間は数年前の情報のため掲載していません。Google マップの登録値を表示します。',
    },
    {
      id: 'kakiraba',
      name: '牡蠣専門居酒屋 カキラバ',
      match: 'カキラバ',
      query: '牡蠣専門居酒屋 カキラバ 沖縄市中央',
      address: null, // 情報源により「中央1-13-6」「中央1-3-7 1F」と食い違うため未記載
      features: [
        'コザウェブでエリア「サンシティ通り」の牡蠣専門居酒屋として掲載されている',
        '牡蠣メニューのほか 40 品以上のフードがあると紹介されている',
      ],
      sources: [
        { label: 'コザウェブ (EN)', url: 'https://en.kozaweb.jp/eats/show/366' },
      ],
      note: '住所表記が情報源で一致しないため、位置は Google Places の結果のみを使用します。',
    },
  ],
};

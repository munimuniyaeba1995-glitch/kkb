# KOZA NIGHT WALK

沖縄市コザ・サンシティ通りのバーチャル飲み歩き。API キー不要・ビルド不要の静的サイト。使い方と構成は README.md。

## 守ること

- API キー・会員登録・課金が必要なサービスを使わない（Google Maps Platform、Mapbox など不可）。
- 架空の店舗・位置・営業時間・写真を入れない。店舗は実行時に OpenStreetMap（Overpass）から取得し、無い項目は「OSM に登録なし」と出す。`js/data.js` の `notes` は出典付きの事実のみ、座標は書かない。
- 実データ（OSM の道路・建物・店舗）と演出（カメラ、夜景フィルター、UI）を画面と文書で区別する。
- 著作権表示（© OpenStreetMap contributors、OpenFreeMap / OpenMapTiles）を消さない。Overpass は結果をキャッシュして負荷を抑える。
- 地図やデータが取れなくても画面を出す（ベクター → OSM ラスター → 無地 → デモ画面）。理由を必ず表示する。
- `js/app.js` から地図ライブラリを直接呼ばない。地図操作は `js/map-maplibre.js` のアダプター経由（仕様は同ファイル冒頭）。

## 検証

開発環境から OSM / OpenFreeMap に届かない場合は、Playwright で `tiles.openfreemap.org`・`tile.openstreetmap.org`・Overpass をモックして確認する（偽データはリポジトリに入れない）。実データでの確認が済んだら README の「検証状況」を更新する。

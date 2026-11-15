# KOZA NIGHT WALK

沖縄市コザ・サンシティ通りのバーチャル飲み歩き。ビルド不要の静的サイト（`index.html` / `css/style.css` / `js/data.js` / `js/app.js`）。使い方と API は README.md。

## 守ること

- 架空の店舗・位置・営業時間を入れない。`js/data.js` は出典付きの事実のみ。緯度経度・営業時間・写真は実行時に Google Places から取得し、取れなければ「確認できませんでした」と出す。
- 実データ（Google の地形・道路・店舗）と演出（カメラ、夜景フィルター、UI）を画面と文書で区別する。
- API キーをリポジトリに入れない（localStorage か `?key=`）。
- 3D Tiles が使えない時は通常地図へ、ストリートビューが無い時は上空ビューのまま、必ず理由を表示する。

## 構成（js/app.js）

- `CesiumAerial`（3D Tiles）と `MapAerial`（2D フォールバック）は同じインターフェース: `fly / cancel / setStores / setPath / setCurrent / sampleGround`。
- `Ground` は Street View。`walkTo` はパノラマの接続をたどって実際の道を歩く。
- `startTour` が自動ツアーの状態機械。`gate()` で一時停止・終了を扱う。
- Cesium は `Viewer` を作ってから `Cesium3DTileset` を作る（逆順だと初期化エラー）。

## 検証

CesiumJS は CDN 読み込み。開発環境から CDN や実 API に届かない場合は、Playwright で CDN を npm の `cesium@1.135.0` に差し替え、Google API をモックして確認する。実キーでの確認が済んだら README の「検証状況」を更新する。

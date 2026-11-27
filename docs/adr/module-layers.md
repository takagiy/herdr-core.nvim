# core・adapter・ui を app がつなぐ 4 層に分け、core は state と event から新しい state と effect を返す

## 状況

判断（スペースの決め方、配置の同期、done の扱い、サイドバーの並び）を、Neovim と hc なしでテストしたい。Neovim の画面の操作と hc の呼び出しは、判断と混ぜたくない。

## 決定

- 4 つの層に分ける。
  - `core/`: 状態と判断。自分の state、event、effect の形だけを知る。入出力はしない。
  - `adapter/`: 外部（hc、git、OS の通知）とのやりとり。判断はしない。
  - `ui/`: Neovim の画面と操作。判断はしない。
  - `app/`: 層をつなぐ。
- core は、state と event を受け取り、新しい state と effect の一覧を返す。event と effect は、ただの Lua のテーブルにする。
- 外部の情報が要る判断は、core が「調べて」という effect を出し、結果を event で受け取る。

## 結果

得たもの:

- 判断はすべて core にあり、テーブルを渡して返ってきたテーブルを確かめるだけでテストできる。
- hc の API が変わっても、直すのは adapter だけで済む。

失ったもの:

- 外部の情報が要る判断は、effect と event の往復になり、直接呼ぶより手順が増える。
- 層ごとのテストでは、層の間の受け渡しの漏れを見つけられない。app を通したテストが要る。

## 採らなかった案

- 3 層（core、adapter、ui）だけにする。event を core に渡して effect を実行する役の置き場がない。
- core が adapter や ui の関数を直接呼ぶ（関数を注入する）。core のテストに偽の関数が要り、呼んだ順番も確かめる必要が出る。

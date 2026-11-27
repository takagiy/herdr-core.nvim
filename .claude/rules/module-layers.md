# モジュールのレイヤー

コードは 4 つのレイヤーに分ける。判断を Neovim と hc なしでテストできるようにするため（理由は docs/adr/module-layers.md）。

- `core/`: 状態と判断。`update(state, event) → state, effects` と `view(state)` だけ。入出力をせず、Neovim の画面や hc を知らない。利用者の関数を state や effect に入れてよいが、呼ばない。
- `adapter/`: 外部（hc、git、OS、利用者のモニター）とのやりとりと、そのデータの変換。判断しない。
- `ui/`: Neovim の画面と操作。読んだことと操作を報告し、言われたとおりに描く。判断しない。
- `app/`: レイヤーをつなぐ。ui と adapter の報告を event にして core に渡し、effect を実行する。
- 外部の情報が要る判断は、core が effect で頼み、結果を event で受け取る。

新しい処理を書くときは、まず判断がどこにあるかを決め、core 以外に判断が入りそうなら core に移す。

レイヤーごとのテストでは、レイヤーの間の受け渡しの漏れを見つけられない。新しい event や effect のフィールドを足したら、app を通したテスト（tests/app/）も書く。

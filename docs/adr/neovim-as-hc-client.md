# herdr TUI の代わりに、Neovim を herdr-core（hc）のクライアントにする

## 状況

herdr の開発の中心は、herdr TUI から herdr-core（コマンドは `hc`）とデスクトップアプリに移っている。TUI を herdr-core の上に移すかは未定とされている（[herdr-app#63](https://github.com/herdrdev/herdr-app/issues/63)）。

hc は、プログラムを閉じても動き続けるターミナルで動かすが、画面は持たない。ペインやタブは、クライアントが用意する。

## 決定

- WezTerm の中で Neovim を 1 つ起動し、エージェントやシェルを、その中のターミナルのバッファー（`hc attach`）で動かす。
- herdr の見た目は再現しない。herdr でできたこと（並べる、プロジェクトごとにまとめる、状態を見る、通知を受ける）を、Neovim のタブページとウィンドウで実現する。
- エージェントの状態（`working` / `blocked` / `done` / `idle`）は、プログラムが OSC 7501 で報告したものだけを使う。hc も、画面の文字からは推測しない。

## 結果

得たもの:

- Neovim を閉じても、エージェントは hc の core で動き続ける。
- ファイルの編集とエージェントの操作が、同じ Neovim でできる。
- Neovim の `:terminal` から、`ctrl+enter` で Claude Code に送信できた（Neovim 0.11.7、hc 0.1.21）。

失ったもの:

- herdr TUI のプラグイン（herdr-nvim、herdr-tsk、herdr-session-transfer、Ovis）は使えない。
- OSC 7501 を出さないプログラムは、状態が分からない。手元の Claude Code 2.1.292 は出していない。2.1.316 以降は出すと報告されている（[herdr-app#325](https://github.com/herdrdev/herdr-app/issues/325)）が、手元では確かめていない。

## 採らなかった案

- WezTerm のペインで `hc attach` を並べ、Neovim は一覧と操作だけを担当する。配置が WezTerm と Neovim の 2 か所に分かれる。
- herdr TUI を使い続ける。当面は動くが、今後の方針が決まっていない。

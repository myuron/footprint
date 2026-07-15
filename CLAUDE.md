# CLAUDE.md

## プロジェクト概要

claude codeとのやり取りを後から確認する際には、`~/.claude/projects/`のjsonlファイルを確認する必要がある。
しかし、このファイルは人間には優しい表示ではない。
人間でも見やすい構造的な表示を行うことで、ユーザのデバッグを手助けするツールを目的としている。
TUIツールなので、Ratatui(TUIフレームワーク)で実装

## ディレクトリ構成

## 技術スタック

- プログラミング言語: Rust
- TUIフレームワーク: Ratatui
- 開発環境: Nix

## 設計原則

## コーディング規約

## 作業規約

- Nix developが提供するツール(grepよりripgrep、findよりfdなど)を優先して使用してください。必要な場合は`flake.nix`に追加する必要があります。

## Git and GitHub規約

- GitHubのリポジトリに関するコミュニケーション(issue comment, PR description, PR Comment等)には米国英語を使用してください。

## よく使うコマンド

- `nix fmt`: formatterを実行
- `nix run .#lint`: linterを実行
- `nix run .#test`: testを実行
- `nix build`: buildを実行

## docs routing

- `docs/jsonl-format.md`: Claude codeのセッション JSONL 構造仕様

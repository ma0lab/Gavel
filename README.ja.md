<div align="center">

# Gavel

**Claude Code をより快適に使うための macOS メニューバーアプリ**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/ma0lab/Gavel/releases/latest)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ma0lab)

[English](README.md)

</div>

---

[Claude Code](https://claude.ai/code) はファイルの書き込みやコマンド実行、Web アクセスなどのツールを使う前に許可を求めます。デフォルトではターミナルで `y` か `n` を入力する必要があります。Gavel はそのリクエストをネイティブの macOS UI で表示し、フォーカスを切り替えずに承認・拒否できるようにします。

## 機能

**承認 UI**
- 承認待ちのリクエストがあるとメニューバーアイコンがベルアニメーションで通知
- ツール名・入力内容・作業ディレクトリを表示するネイティブ承認ウィンドウ
- 誤操作防止のための 2 ステップ拒否確認
- グローバルキーボードショートカットで即アクセス

**自動許可ルール**
- ツール名・ファイルパスパターン・コマンドパターンでルールを定義
- マッチしたリクエストは自動承認され、作業を中断しない

**レートリミット**
- 5時間・7日間の使用量をプログレスバーで表示
- タップで数値表示に切り替え可能
- リセット時刻をローカルタイムゾーンで表示 — 例: `あと 2時間14分 でリセット (今日 23:48)`

**アクティビティ**
- セッションごとのツール呼び出し回数
- 最大 5,000 件のアクティビティログ

**音声入力** *(要 [whisper.cpp](https://github.com/ggerganov/whisper.cpp))*
- プッシュトゥトークで前面アプリに直接入力
- フィラーワード除去・語彙補正
- 音声履歴からの再ペースト

**その他**
- 画面ロック・スリープ・アイドル時に自動で一時停止、復帰時に再有効化

## 動作環境

- macOS 13 Ventura 以降
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) インストール済み

## インストール

1. [最新リリース](https://github.com/ma0lab/Gavel/releases/latest) から `Gavel.dmg` をダウンロード
2. DMG を開き **Gavel.app** を Applications フォルダにドラッグ
3. Gavel を起動 — メニューバーに `>_` として表示されます
4. アプリ内のセットアップ画面に従って Claude Code と連携

> **Gatekeeper について**: それでも macOS にブロックされる場合は、システム設定 → プライバシーとセキュリティ → 「このまま開く」を選択してください。

## ライセンス

MIT — [LICENSE](LICENSE) を参照

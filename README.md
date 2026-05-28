<div align="center">

# Gavel

**A macOS menu bar companion for Claude Code**

[![License: MIT](https://img.shields.io/badge/License-MIT-blue.svg)](LICENSE)
[![Platform](https://img.shields.io/badge/platform-macOS%2013%2B-lightgrey)](https://github.com/ma0lab/Gavel/releases/latest)
[![Ko-fi](https://img.shields.io/badge/Ko--fi-support-ff5e5b?logo=ko-fi&logoColor=white)](https://ko-fi.com/ma0lab)

<br>

[English](#english) &nbsp;·&nbsp; [日本語](#日本語)

</div>

---

<a name="english"></a>

## English

Claude Code asks for permission before running tools like writing files, executing commands, or making web requests. By default you answer `y` or `n` in the terminal. Gavel intercepts those requests and surfaces them in a native macOS UI — so you can approve or deny without switching focus, set up auto-allow rules for repetitive operations, and keep an eye on your rate limits from the menu bar.

### Features

**Approval UI**
- Bell animation on the menu bar icon when a request is waiting
- Native approval window with full context: tool name, input, working directory
- Two-step confirmation for deny to avoid accidental rejections
- Keyboard shortcut to open the approval window from anywhere

**Auto-allow rules**
- Define rules by tool name, file path pattern, or command pattern
- Matching requests are approved instantly without interrupting you

**Rate limits**
- 5-hour and 7-day usage displayed as progress bars in the menu popup
- Tap to switch between bar view and number view
- Reset time shown in your local timezone — e.g. `resets in 2h 14m (today 23:48)`

**Activity**
- Per-session tool call counts
- Full activity log (up to 5,000 entries)

**Voice input** *(requires [whisper.cpp](https://github.com/ggerganov/whisper.cpp))*
- Push-to-talk dictation into the frontmost app
- Filler word removal and vocabulary correction
- Voice history: re-paste recent dictations from the menu

**Quality of life**
- Auto-disables interception on screen lock, sleep, or idle
- Re-enables automatically on wake

### Requirements

- macOS 13 Ventura or later
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) installed

### Installation

1. Download `Gavel.dmg` from the [latest release](https://github.com/ma0lab/Gavel/releases/latest)
2. Open the DMG and drag **Gavel.app** to your Applications folder
3. Launch Gavel — it appears in your menu bar as `>_`
4. Follow the in-app setup to connect it to Claude Code

> **Gatekeeper note**: Gavel is signed with a Developer ID certificate. If macOS blocks it, go to System Settings → Privacy & Security → open anyway.

### License

MIT — see [LICENSE](LICENSE)

---

<a name="日本語"></a>

## 日本語

[Claude Code](https://claude.ai/code) はファイルの書き込みやコマンド実行、Web アクセスなどのツールを使う前に許可を求めます。デフォルトではターミナルで `y` か `n` を入力する必要があります。Gavel はそのリクエストをネイティブの macOS UI で表示し、フォーカスを切り替えずに承認・拒否できるようにします。

### 機能

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

### 動作環境

- macOS 13 Ventura 以降
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) インストール済み

### インストール

1. [最新リリース](https://github.com/ma0lab/Gavel/releases/latest) から `Gavel.dmg` をダウンロード
2. DMG を開き **Gavel.app** を Applications フォルダにドラッグ
3. Gavel を起動 — メニューバーに `>_` として表示されます
4. アプリ内のセットアップ画面に従って Claude Code と連携

> **Gatekeeper について**: それでも macOS にブロックされる場合は、システム設定 → プライバシーとセキュリティ → 「このまま開く」を選択してください。

### ライセンス

MIT — [LICENSE](LICENSE) を参照

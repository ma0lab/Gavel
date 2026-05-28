# Gavel

[Claude Code](https://claude.ai/code) をより快適に使うための macOS メニューバーアプリです。

[![Ko-fi](https://ko-fi.com/img/githubbutton_sm.svg)](https://ko-fi.com/ma0lab)

![Gavel スクリーンショット](docs/screenshot.png)

## 概要

Claude Code はファイルの書き込みやコマンド実行、Web アクセスなどのツールを使う前に許可を求めます。デフォルトではターミナルで `y` か `n` を入力する必要があります。Gavel はそのリクエストをネイティブの macOS UI で表示し、フォーカスを切り替えずに承認・拒否できるようにします。繰り返し操作の自動許可設定や、メニューバーからのレートリミット確認にも対応しています。

## 機能

**承認 UI**
- 承認待ちのリクエストがあるとメニューバーアイコンがベルアニメーションで通知
- ツール名・入力内容・作業ディレクトリを表示するネイティブ承認ウィンドウ
- 誤操作防止のための2ステップ拒否確認
- どこからでも承認ウィンドウを開けるグローバルキーボードショートカット

**自動許可ルール**
- ツール名・ファイルパスパターン・コマンドパターンでルールを定義
- マッチしたリクエストは自動で承認され、作業を中断しない

**レートリミット**
- 5時間・7日間の使用量をメニューポップアップにプログレスバーで表示
- タップで数値表示に切り替え可能
- リセット時刻をローカルタイムゾーンで表示 — 例: `あと 2時間14分 でリセット (今日 23:48)`

**アクティビティ**
- セッションごとのトークン使用量とツール呼び出し回数
- 最大5,000件のアクティビティログ

**音声入力** *(要 [whisper.cpp](https://github.com/ggerganov/whisper.cpp))*
- プッシュトゥトーク方式の音声入力 — 前面アプリにそのまま挿入
- フィラーワード除去・語彙補正
- 音声履歴: 最近の入力テキストをメニューから再ペースト

**その他**
- 画面ロック・スリープ・アイドル時に自動で承認インターセプトを無効化（復帰時に再有効化）
- アイドル閾値: 60秒間入力がないと自動で一時停止

## 動作環境

- macOS 13 Ventura 以降
- Apple Silicon (arm64)
- [Claude Code](https://claude.ai/code) インストール済み

## インストール

1. [最新リリース](https://github.com/ma0lab/Gavel/releases/latest) から `Gavel.dmg` をダウンロード
2. DMG を開き **Gavel.app** を Applications フォルダにドラッグ
3. Gavel を起動 — メニューバーに `>_` として表示されます
4. アプリ内のセットアップ画面に従って Claude Code と連携

> **Gatekeeper について**: Gavel は Developer ID 証明書で署名されています。それでも macOS にブロックされる場合は、システム設定 → プライバシーとセキュリティ → 「このまま開く」を選択してください。

## レートリミット連携

Gavel は Claude Code の [statusline API](https://docs.anthropic.com/en/docs/claude-code/settings#status-line-customization) からレートリミット情報を読み取ります。有効にするには `~/.claude/settings.json` に以下を追加してください:

```json
{
  "statusCommand": "python3 ~/.claude/statusline.py"
}
```

次に `~/.claude/statusline.py` を作成します:

```python
import sys, json, time

data = json.load(sys.stdin)

# Gavel 用にレートリミット情報を書き出す
rl = data.get('rate_limits', {})
five_h = rl.get('five_hour')
seven_d = rl.get('seven_day')
if five_h or seven_d:
    payload = {'updated_at': time.time()}
    if five_h:
        payload['five_hour'] = five_h
    if seven_d:
        payload['seven_day'] = seven_d
    try:
        with open('/tmp/gavel_ratelimits.json', 'w') as f:
            json.dump(payload, f)
    except Exception:
        pass

# ステータスラインに表示する内容（自由にカスタマイズ可）
sessions = data.get('sessions', [])
if sessions:
    total = sum(s.get('total_cost_usd', 0) for s in sessions)
    print(f"${total:.2f} today")
```

## ソースからビルド

```bash
git clone https://github.com/ma0lab/Gavel.git
cd Gavel
make build        # dist/Gavel.app をビルド
make deploy       # ビルド + /Applications にインストール + 起動
make dmg          # 配布用 DMG を作成
```

Xcode Command Line Tools と有効な Developer ID 証明書が必要です。

## ライセンス

MIT

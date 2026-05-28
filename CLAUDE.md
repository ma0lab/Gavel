# Gavel

## UserDefaultsの書き込みルール

GavelのUserDefaults（`com.maolab.Gavel`）を外部から書き込む場合は、**必ず `defaults write` を使う**。plistファイルへの直接書き込みは禁止。

**理由**: plistに直接書くとcfprefsd（UserDefaultsキャッシュデーモン）をバイパスするため、アプリが古い値を読み続ける。

### autoAllowRulesの更新手順

```python
import json, subprocess, plistlib

plist_path = '/Users/mao/Library/Preferences/com.maolab.Gavel.plist'

# 読み込み（plistから）
subprocess.run(['plutil', '-convert', 'xml1', plist_path], capture_output=True)
with open(plist_path, 'rb') as f:
    plist = plistlib.load(f)
rules = json.loads(plist['autoAllowRules'])

# ルールを編集する
# ...

# 書き込み（defaults write経由）
json_bytes = json.dumps(rules, ensure_ascii=False, separators=(',', ':')).encode('utf-8')
subprocess.run(['defaults', 'write', 'com.maolab.Gavel', 'autoAllowRules', '-data', json_bytes.hex()])
```

書き込み後はGavelの「Restart Gavel」（右クリックメニュー）で再起動して反映させる。

## ビルド・デプロイ

```bash
make deploy
```

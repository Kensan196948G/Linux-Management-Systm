# CI スクリプト

**自動ビルド・テスト・修復スクリプト**

---

## 📋 概要

CI/CD パイプラインで使用するビルド・テスト・自動修復スクリプト群。

---

## 📂 ファイル一覧

| ファイル | OS | 用途 |
|---------|-----|------|
| `build.sh` | Linux/macOS | 統合ビルド・テストスクリプト |
| `build.ps1` | Windows | 統合ビルド・テストスクリプト |
| `auto_fix_with_claudecode.sh` | Linux | Claude Code 自動修復 |
| `guard_changes.sh` | Linux | 暴走防止ガードチェック |

---

## 🚀 使い方

### ローカルでビルドを実行

#### Linux / macOS

```bash
# ビルド実行
bash ci/build.sh

# 失敗した場合、ログを確認
cat build.log
```

#### Windows (PowerShell)

```powershell
# ビルド実行
.\ci\build.ps1
```

---

## 🔄 自動修復ループ（GitHub Actions）

### フロー

```
① ビルド実行（build.sh）
  ↓ 失敗
② ビルドログを保存（build.log）
  ↓
③ ガードチェック（guard_changes.sh）
  ├─ 試行回数チェック（最大5回）
  ├─ 同一エラー検出
  ├─ 差分量制限（20行）
  └─ 対象ファイル制限（.py, .sh のみ）
  ↓ PASS
④ 修復プロンプト生成（auto_fix_with_claudecode.sh）
  ↓
⑤ Artifacts にアップロード
  ↓
⑥ 人間が Claude Code で修復
  ↓
⑦ git commit & push
  ↓
⑧ GitHub Actions 再実行
```

---

## 📋 build.sh / build.ps1 の内容

### チェック項目

1. **Shell スクリプト構文チェック**
   - ShellCheck によるラッパースクリプト検証

2. **Python 構文チェック・Lint**
   - py_compile で構文チェック
   - flake8 で Lint

3. **セキュリティスキャン**
   - Bandit で HIGH/CRITICAL issues チェック

4. **禁止パターン検出**
   - shell=True 検出
   - os.system 検出
   - eval/exec 検出

5. **単体テスト実行**
   - pytest 全テスト実行
   - カバレッジ測定

6. **ラッパースクリプトテスト**
   - wrappers/test/test-all-wrappers.sh 実行

---

## 🛡️ ガードチェック（暴走防止）

### 1. 無限ループ防止

```bash
最大試行回数: 5回
カウンターファイル: .ci_attempt_count

試行回数を超えた場合 → 即座に停止
```

### 2. 同一エラー検出

```bash
エラーハッシュ: SHA1
ハッシュファイル: .ci_error_hash

同じエラーが繰り返された場合 → 停止
```

### 3. 差分量制限

```bash
最大差分: 20行

大規模な変更 → 手動レビューが必要
```

### 4. 対象ファイル制限

```bash
許可ファイル: .py, .sh, ci/*

その他のファイル（.yml, .md など）→ 拒否
```

---

## 🤖 Claude Code 自動修復

### 修復プロンプトの構造

```
あなたは CI 修理工エージェントです。

以下のビルド失敗ログを確認してください:
---
<build.log の内容>
---

修復ルール:
- Python ファイル（.py）のみを修正
- Shell スクリプト（.sh）も必要に応じて修正可能
- 差分は最小限に（1-5行程度）
- リファクタリングは行わない
- 新しい依存関係は追加しない

タスク:
ビルドが成功するよう、根本原因のみを修正してください。
```

---

## 📊 GitHub Actions での使用

### 手動トリガー

1. GitHub リポジトリの **Actions** タブに移動
2. **Auto Fix Loop** ワークフローを選択
3. **Run workflow** をクリック
4. 実行後、Artifacts から以下をダウンロード:
   - `build-log-XXX`: ビルドログ
   - `repair-prompt-XXX`: 修復プロンプト

5. repair-prompt の内容を Claude Code に送信
6. 修正されたコードを確認・コミット
7. プッシュすると自動的に再ビルド

---

## 🔍 トラブルシューティング

### ビルドが失敗し続ける

```bash
# 1. ローカルでビルドを実行
bash ci/build.sh

# 2. どのステップで失敗しているか確認
# 3. 手動で修正

# 4. カウンターをリセット
rm .ci_attempt_count .ci_error_hash
```

### ガードチェックが厳しすぎる

```bash
# guard_changes.sh の設定を調整
# MAX_ATTEMPTS, MAX_DIFF_LINES など
```

---

## 📚 参考資料

- [.github/workflows/auto-fix-loop.yml](../.github/workflows/auto-fix-loop.yml)
- [CLAUDE.md](../CLAUDE.md) - セキュリティ原則
- [agents/07_ci-specialist.md](../agents/07_ci-specialist.md) - CI SubAgent

---

## ⚠️ 重要な注意事項

### 1. 半自動システム

現在の実装は**半自動**です：
- ビルド失敗検出: 自動
- 修復プロンプト生成: 自動
- **修復実行: 手動**（Claude Code で）
- コミット・プッシュ: 手動

### 2. 完全自動化への拡張

Claude Code API を統合すれば、完全自動化が可能ですが：
- セキュリティリスクを十分に評価
- 本番環境では慎重に有効化
- 人間承認のゲートを設ける

### 3. ITSM 準拠

- 全ビルドログを保存（監査証跡）
- 全 diff を保存（変更追跡）
- 失敗・成功の完全な記録

---

**最終更新**: 2026-02-05

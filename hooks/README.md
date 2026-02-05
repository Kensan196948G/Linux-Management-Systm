# Hooks - ワークフロー自動化

**SubAgent 間の連携を自動化する Hooks システム**

---

## 📋 概要

本ディレクトリには、SubAgent 間のワークフロー遷移を自動化し、並列実行時のコンフリクトを防止する Hooks スクリプトが含まれています。

---

## 🪝 Hooks 一覧

| Hook | トリガー | アクション |
|------|---------|-----------|
| **on-spec-complete** | specs/* 生成完了 | arch-reviewer 自動起動 |
| **on-arch-approved** | アーキテクチャレビュー PASS | code-implementer 自動起動 |
| **on-implementation-complete** | 実装完了宣言 | code-reviewer 自動起動 |
| **on-code-review-result** | コードレビュー結果返却 | 結果に応じて分岐 |
| **on-test-design-complete** | テスト設計完了 | test-reviewer 自動起動 |
| **on-test-review-result** | テストレビュー結果返却 | ci-specialist 自動起動（PASS時） |

---

## 📂 ファイル構成

```
hooks/
├── workflow-engine.sh           # メインワークフローエンジン
├── conflict-prevention.sh       # 並列実行・コンフリクト防止
└── README.md                    # このファイル
```

---

## 🚀 使い方

### 基本的な使用方法

```bash
# Hook を手動で起動
./hooks/workflow-engine.sh on-spec-complete

# ワークフロー状態を確認
cat .workflow-state.json

# ログを確認
tail -f workflow.log
```

### ワークフロー全体の流れ

```bash
# 1. 要件定義完了後
./hooks/workflow-engine.sh on-spec-complete
# → arch-reviewer が自動起動

# 2. アーキテクチャレビュー完了後
./hooks/workflow-engine.sh on-arch-approved
# → code-implementer が自動起動

# 3. 実装完了後
./hooks/workflow-engine.sh on-implementation-complete
# → code-reviewer が自動起動

# 4. コードレビュー完了後
./hooks/workflow-engine.sh on-code-review-result
# → 結果に応じて test-designer 起動 or 差し戻し

# 5. テスト設計完了後
./hooks/workflow-engine.sh on-test-design-complete
# → test-reviewer が自動起動

# 6. テストレビュー完了後
./hooks/workflow-engine.sh on-test-review-result
# → ci-specialist が自動起動
```

---

## 🔒 並列実行・コンフリクト防止

### ファイルロックの取得・解放

```bash
# ファイルをロック（編集開始時）
./hooks/conflict-prevention.sh acquire backend/api/main.py code-implementer

# ファイルのロックを解放（編集完了時）
./hooks/conflict-prevention.sh release backend/api/main.py code-implementer
```

### 複数ファイルの一括登録

```bash
# 複数ファイルを一括でロック
./hooks/conflict-prevention.sh register code-implementer \
    backend/api/main.py \
    backend/core/auth.py \
    backend/core/permissions.py

# 一括解放
./hooks/conflict-prevention.sh unregister code-implementer \
    backend/api/main.py \
    backend/core/auth.py \
    backend/core/permissions.py
```

### ロック状態の確認

```bash
# 現在のロック状態を表示
./hooks/conflict-prevention.sh status

# 出力例:
# 📊 Current lock status:
#    🔒 backend/api/main.py - locked by code-implementer:12345:2026-02-05T11:00:00+09:00
```

### 緊急時の全ロッククリーンアップ

```bash
# 全てのロックを強制解除
./hooks/conflict-prevention.sh cleanup
```

---

## 🔄 並列実行ルール

### 常時並列実行可能

以下の SubAgent は**常時並列実行**が可能です：

```bash
arch-reviewer + security + qa
```

これらは同時に動作しても競合しません。

### 逐次実行（ファイルロック必須）

以下の SubAgent はファイルロックが必要です：

```bash
code-implementer
```

同一ファイルへの同時書き込みを防止します。

---

## 📊 ワークフロー状態の管理

### 状態ファイル

```json
{
  "current_phase": "implementation",
  "last_agent": "code-implementer",
  "timestamp": "2026-02-05T11:00:00+09:00"
}
```

### フェーズ一覧

| フェーズ | 説明 |
|---------|------|
| `idle` | 待機中 |
| `spec-planning` | 要件定義中 |
| `arch-review` | アーキテクチャレビュー中 |
| `implementation` | 実装中 |
| `code-review` | コードレビュー中 |
| `implementation-rework` | 実装修正中 |
| `test-design` | テスト設計中 |
| `test-review` | テストレビュー中 |
| `test-design-rework` | テスト設計修正中 |
| `ci-design` | CI設計中 |

---

## 🔍 トラブルシューティング

### ロックがスタックした場合

```bash
# 1. ロック状態を確認
./hooks/conflict-prevention.sh status

# 2. 特定のファイルのロックを強制解除
rm -rf .workflow-locks/backend_api_main.py.lock

# 3. または全ロックをクリーンアップ
./hooks/conflict-prevention.sh cleanup
```

### ワークフローがスタックした場合

```bash
# 1. 現在の状態を確認
cat .workflow-state.json

# 2. ログを確認
tail -100 workflow.log

# 3. 必要に応じて状態をリセット
rm .workflow-state.json
```

---

## 🎯 実装例

### code-implementer での使用例

```bash
#!/bin/bash
# code-implementer の実装スクリプト例

AGENT_NAME="code-implementer"
FILES_TO_EDIT=(
    "backend/api/routes/services.py"
    "backend/core/permissions.py"
)

# 1. ファイルをロック
./hooks/conflict-prevention.sh register "$AGENT_NAME" "${FILES_TO_EDIT[@]}"

# 2. 実装作業
echo "Implementing..."
# ... 実際の実装処理 ...

# 3. ファイルのロックを解放
./hooks/conflict-prevention.sh unregister "$AGENT_NAME" "${FILES_TO_EDIT[@]}"

# 4. 実装完了を通知
./hooks/workflow-engine.sh on-implementation-complete
```

---

## 📚 関連ドキュメント

- [agents/README.md](../agents/README.md) - SubAgent 7体構成
- [CLAUDE.md](../CLAUDE.md) - セキュリティ原則
- [README.md](../README.md) - プロジェクト概要

---

## ⚙️ 高度な使用方法

### ファイル監視による自動起動（将来実装）

```bash
# inotify-tools を使用した自動監視
inotifywait -m -e close_write specs/ | while read path action file; do
    if [[ "$file" == "overview.md" ]] || [[ "$file" == "requirements.md" ]]; then
        ./hooks/workflow-engine.sh on-spec-complete
    fi
done
```

### GitHub Actions との連携

```yaml
# .github/workflows/hooks.yml
name: Workflow Hooks

on:
  push:
    paths:
      - 'specs/**'
      - 'design/**'

jobs:
  trigger-hooks:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Detect changes and trigger hooks
        run: |
          if git diff --name-only HEAD^ HEAD | grep -q "specs/"; then
            ./hooks/workflow-engine.sh on-spec-complete
          fi
```

---

## 🚫 禁止事項

1. **Hooks のスキップ禁止**
   - 工程遷移は必ず Hooks 経由で行う

2. **手動での状態ファイル編集禁止**
   - `.workflow-state.json` は自動生成のみ

3. **ロック機構のバイパス禁止**
   - ファイル編集時は必ずロック取得

---

## 🎯 成功基準

Hooks システムが以下を満たすこと：

1. ✅ 全工程遷移が自動化されている
2. ✅ 並列実行時の競合が発生しない
3. ✅ ワークフロー状態が追跡可能
4. ✅ ロックタイムアウトが適切に処理される
5. ✅ ログが完全に記録される

---

**最終更新**: 2026-02-05

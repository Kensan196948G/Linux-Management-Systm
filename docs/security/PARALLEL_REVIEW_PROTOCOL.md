# Running Processes モジュール - 並列レビュープロトコル

**作成日**: 2026-02-06
**レビュアー**: security-checker
**ステータス**: 🟢 監視待機中（Monitoring Standby）

---

## 🎯 並列レビューミッション

security-checker は、Running Processes モジュールの実装フェーズにおいて、**全実装コードを並列レビュー**し、セキュリティ違反を即座に検出・報告する。

---

## 📋 監視対象

### 1. backend-impl（バックエンド実装）

**監視ファイル**:
- `backend/api/routes/processes.py` - API エンドポイント
- `backend/core/sudo_wrapper.py` - ラッパー呼び出しロジック（修正）
- `backend/core/process_manager.py` - プロセス管理ロジック（新規）

**重点チェック項目**:
- [ ] `shell=True` の検出 → 即座に停止
- [ ] `os.system` の検出 → 即座に停止
- [ ] `eval` / `exec` の検出 → 即座に停止
- [ ] Pydantic バリデーション実装確認
- [ ] FORBIDDEN_CHARS チェック実装確認
- [ ] 機密情報マスク処理の実装確認
- [ ] 監査ログ記録の実装確認
- [ ] レート制限の実装確認
- [ ] RBAC の実装確認

---

### 2. frontend-impl（フロントエンド実装）

**監視ファイル**:
- `frontend/processes.html` - プロセス管理画面
- `frontend/js/processes.js` - クライアント側ロジック

**重点チェック項目**:
- [ ] XSS 対策（HTML エスケープ）
- [ ] CSRF トークンの実装
- [ ] クライアント側の入力検証
- [ ] 機密情報の表示制御
- [ ] エラーメッセージの適切な表示

---

### 3. test-designer（テスト実装）

**監視ファイル**:
- `tests/security/test_processes_security.py` - セキュリティテスト
- `tests/unit/test_processes.py` - ユニットテスト
- `tests/integration/test_processes_api.py` - 統合テスト

**重点チェック項目**:
- [ ] セキュリティテスト 50+ ケース実装
- [ ] コマンドインジェクションテスト 15+ ケース
- [ ] PID バリデーションテスト 8+ ケース
- [ ] RBAC テスト 8+ ケース
- [ ] カバレッジ 90%+ 達成

---

### 4. wrapper-impl（ラッパースクリプト実装）

**監視ファイル**:
- `wrappers/adminui-processes.sh` - プロセス情報取得ラッパー

**重点チェック項目**:
- [ ] `set -euo pipefail` の実装
- [ ] 特殊文字検証の実装
- [ ] `bash -c` の検出 → 即座に停止
- [ ] `eval` の検出 → 即座に停止
- [ ] 引用符の適切な使用
- [ ] 配列渡しの実装
- [ ] ログ記録の実装

---

## 🚨 即座停止パターン（Critical Violations）

以下のパターンを検出した場合、**即座に実装を停止**し、team-lead に報告：

### Python（backend）

```python
# ❌ CRITICAL VIOLATION - 即座停止
subprocess.run("...", shell=True)
os.system("...")
eval(user_input)
exec(user_input)
__import__(user_input)
```

### Bash（wrappers）

```bash
# ❌ CRITICAL VIOLATION - 即座停止
bash -c "..."
eval "..."
sudo systemctl restart $SERVICE  # 引用符なし
```

---

## ⚠️ 警告パターン（High Priority Warnings）

以下のパターンを検出した場合、**警告を発し、修正を要求**：

### Python

```python
# ⚠️ WARNING - 修正要求
# Pydantic バリデーションなし
filter_str = request.args.get("filter")  # 検証なし

# 監査ログなし
result = sudo_wrapper.get_processes(filter_str)
return result  # ログ記録なし

# 機密情報マスクなし
return {"cmdline": process.cmdline}  # マスク処理なし
```

### Bash

```bash
# ⚠️ WARNING - 修正要求
# 特殊文字検証なし
FILTER="$1"
ps aux | grep $FILTER  # 検証なし

# 引用符なし
if [ $PID -gt 0 ]; then  # "$PID" にすべき
```

---

## 📊 レビュープロセス

### Step 1: コード検出
- Git commit を監視（または実装者からの通知）
- 新規ファイル・変更ファイルを検出

### Step 2: 静的解析
```bash
# Bandit スキャン
bandit -r backend/api/routes/processes.py -ll

# ShellCheck
shellcheck wrappers/adminui-processes.sh

# Grep パターン検出
grep -r "shell=True" backend/api/routes/processes.py
grep -r "bash -c" wrappers/adminui-processes.sh
```

### Step 3: コードレビュー
- セキュリティチェックリストに基づく手動レビュー
- SECURITY_REQUIREMENTS_PROCESSES.md との照合

### Step 4: 結果報告
- **違反なし**: team-lead に承認報告
- **警告あり**: 実装者に修正依頼
- **重大違反**: 即座停止、team-lead に緊急報告

---

## 📝 レビュー報告フォーマット

### ✅ 承認報告（違反なし）

```markdown
## セキュリティレビュー完了 - [ファイル名]

**レビュアー**: security-checker
**対象**: backend/api/routes/processes.py
**ステータス**: ✅ 承認

### 検証項目
- ✅ shell=True 検出: ゼロ件
- ✅ Pydantic バリデーション: 実装済み
- ✅ 監査ログ: 全操作記録
- ✅ 機密情報マスク: 実装済み
- ✅ RBAC: 実装済み

### 静的解析結果
- Bandit: No issues identified
- Grep: 禁止パターンゼロ検出

**結論**: セキュリティ要件を満たしており、承認します。
```

---

### ⚠️ 警告報告（修正要求）

```markdown
## セキュリティレビュー - 警告 [ファイル名]

**レビュアー**: security-checker
**対象**: backend/api/routes/processes.py
**ステータス**: ⚠️ 修正要求

### 検出された問題（3件）

#### 1. 監査ログ記録漏れ（High）
- **場所**: processes.py:123
- **問題**: `list_processes()` で監査ログが記録されていない
- **修正**: `audit_log.record(...)` を追加

#### 2. 機密情報マスク不足（High）
- **場所**: processes.py:145
- **問題**: `cmdline` がマスクされずに返される
- **修正**: `mask_sensitive_cmdline()` を呼び出し

#### 3. レート制限未実装（Medium）
- **場所**: processes.py:100
- **問題**: `@limiter.limit()` デコレータがない
- **修正**: `@limiter.limit("60/minute")` を追加

**修正期限**: 即座に修正してください
**再レビュー**: 修正後、再度レビューを実施
```

---

### 🚨 緊急報告（重大違反）

```markdown
## 🚨 CRITICAL SECURITY VIOLATION - 実装停止

**レビュアー**: security-checker
**対象**: backend/api/routes/processes.py
**ステータス**: 🔴 重大違反 - 実装停止

### 検出された重大違反

#### ❌ shell=True の使用（CRITICAL）
- **場所**: processes.py:200
- **コード**:
  ```python
  subprocess.run(f"ps aux | grep {filter_str}", shell=True)
  ```
- **影響**: コマンドインジェクション攻撃の可能性（CVSS 9.8 - CRITICAL）
- **対策**: 即座に削除し、配列渡しに変更

**即座対応**: この実装は CLAUDE.md のセキュリティ原則に違反しており、
             本番環境へのデプロイは絶対に不可。
             即座に修正してください。

**team-lead への報告**: この違反を team-lead に報告し、
                      実装フェーズの一時停止を要請します。
```

---

## 🔄 継続的監視体制

### 監視頻度
- **実装中**: リアルタイム監視（コミット検出時即座にレビュー）
- **実装完了後**: 最終レビュー（全ファイル再チェック）

### 監視ツール
- **Bandit**: Python セキュリティスキャン（自動）
- **ShellCheck**: Bash スクリプト検証（自動）
- **Grep**: 禁止パターン検出（自動）
- **手動レビュー**: セキュリティチェックリストに基づく確認

---

## 📞 エスカレーションパス

```
security-checker
  ↓ 重大違反検出
team-lead
  ↓ 判断
実装停止 or 修正指示
```

---

## ✅ 完了基準

以下の条件を全て満たした場合、並列レビュー完了：

- [ ] 全実装ファイルのレビュー完了
- [ ] 禁止パターンゼロ検出
- [ ] Bandit / ShellCheck 全パス
- [ ] セキュリティチェックリスト全項目クリア
- [ ] テストカバレッジ 90%+ 達成
- [ ] 全テスト PASS

---

**並列レビュー開始日**: 2026-02-06
**現在ステータス**: 🟢 監視待機中

---

**security-checker コミットメント**:
Running Processes モジュールの実装品質を保証し、
CLAUDE.md セキュリティ原則への完全準拠を確保します。

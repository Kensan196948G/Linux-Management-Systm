# Running Processes モジュール レビューチェックリスト

**作成日**: 2026-02-06
**対象**: security-checker, code-reviewer, test-designer, arch-reviewer
**関連**: [processes-module-design.md](./processes-module-design.md)

---

## 🔒 セキュリティレビュー（security-checker）

### 1. CLAUDE.md セキュリティ原則への準拠

#### 1.1 Allowlist First ✅

- [ ] **Wrapper**: `ALLOWED_USERS` 配列が定義されている
- [ ] **Wrapper**: `ALLOWED_SORTS` 配列が定義されている
- [ ] **Wrapper**: allowlist 外の入力を拒否している
- [ ] **API**: Pydantic で許可値を regex 検証している

**検証コマンド**:
```bash
# allowlist の存在確認
grep -n "ALLOWED_USERS" wrappers/adminui-processes.sh
grep -n "ALLOWED_SORTS" wrappers/adminui-processes.sh

# allowlist チェックロジックの確認
grep -A 10 "allowlist" wrappers/adminui-processes.sh
```

#### 1.2 Deny by Default ✅

- [ ] **Wrapper**: デフォルトで拒否、allowlist にある場合のみ許可
- [ ] **Wrapper**: `SERVICE_ALLOWED=false` から開始
- [ ] **API**: 明示的な権限チェック（`require_permission("read:processes")`）

**検証コマンド**:
```bash
# Deny by Default の実装確認
grep -n "SERVICE_ALLOWED=false" wrappers/adminui-processes.sh
grep -n "require_permission" backend/api/routes/processes.py
```

#### 1.3 Shell禁止 ✅

- [ ] **Wrapper**: `shell=True` が使用されていない
- [ ] **Wrapper**: `os.system()` が使用されていない
- [ ] **Wrapper**: `eval()` が使用されていない
- [ ] **Wrapper**: 配列渡しでコマンド実行している
- [ ] **Python**: `subprocess.run(..., shell=False)` または配列渡し

**検証コマンド**:
```bash
# 禁止パターンの検出
grep -r "shell=True" backend/ wrappers/ && echo "❌ shell=True detected" || echo "✅ No shell=True"
grep -r "os.system" backend/ wrappers/ && echo "❌ os.system detected" || echo "✅ No os.system"
grep -r "eval(" backend/ wrappers/ && echo "❌ eval() detected" || echo "✅ No eval()"

# 配列渡しの確認
grep -n 'PS_ARGS=(' wrappers/adminui-processes.sh
grep -n 'ps "${PS_ARGS[@]}"' wrappers/adminui-processes.sh
```

#### 1.4 sudo最小化 ✅

- [ ] **Phase 1**: root 権限不要（`ps aux` はユーザー権限で実行可能）
- [ ] **Wrapper**: sudo なしで実行可能
- [ ] **Phase 2**: プロセス停止時のみ sudo 経由（将来実装）

**検証コマンド**:
```bash
# ps コマンドが sudo なしで実行されているか確認
grep -n "sudo ps" wrappers/adminui-processes.sh && echo "❌ Unnecessary sudo" || echo "✅ No unnecessary sudo"
```

#### 1.5 監査証跡 ✅

- [ ] **API**: 全操作で監査ログ記録（attempt, success, denied, failure）
- [ ] **Wrapper**: logger で操作ログを記録
- [ ] **監査ログ**: 必須項目が含まれている（user_id, operation, target, status, details）

**検証コマンド**:
```bash
# 監査ログの記録確認
grep -n "audit_log.record" backend/api/routes/processes.py
grep -n "logger -t adminui-processes" wrappers/adminui-processes.sh

# 監査ログのステータス網羅性確認
grep "status=" backend/api/routes/processes.py | sort | uniq
```

**期待される監査ログステータス**:
- `attempt` - 操作試行
- `success` - 成功
- `denied` - allowlist 拒否
- `failure` - システムエラー

---

### 2. 入力検証（多層防御）

#### 2.1 特殊文字検証

- [ ] **Wrapper**: `FORBIDDEN_CHARS` パターンが定義されている
- [ ] **Wrapper**: 全入力パラメータで特殊文字をチェック
- [ ] **API**: Pydantic regex で特殊文字を拒否

**禁止文字**: `;`, `|`, `&`, `$`, `(`, `)`, `` ` ``, `>`, `<`, `*`, `?`, `{`, `}`, `[`, `]`

**検証コマンド**:
```bash
# 特殊文字パターンの定義確認
grep -n "FORBIDDEN_CHARS" wrappers/adminui-processes.sh

# 特殊文字チェックの実装確認
grep -n "FORBIDDEN_CHARS" wrappers/adminui-processes.sh | head -5
```

#### 2.2 範囲検証

- [ ] **API**: `limit` が 1-1000 の範囲内（`ge=1, le=1000`）
- [ ] **API**: `min_cpu`, `min_mem` が 0.0-100.0 の範囲内（`ge=0.0, le=100.0`）
- [ ] **Wrapper**: 範囲外の値を拒否

**検証コマンド**:
```bash
# Pydantic 範囲検証の確認
grep -n "ge=" backend/api/routes/processes.py
grep -n "le=" backend/api/routes/processes.py
```

#### 2.3 allowlist 検証

- [ ] **Wrapper**: ユーザー名が allowlist にある場合のみ許可
- [ ] **Wrapper**: ソートキーが allowlist にある場合のみ許可
- [ ] **テスト**: allowlist 外の値が拒否されることを確認

**検証コマンド**:
```bash
# allowlist 検証ロジックの確認
grep -A 10 "validate_user" wrappers/adminui-processes.sh
grep -A 10 "validate_sort_key" wrappers/adminui-processes.sh
```

---

### 3. 情報漏洩対策

#### 3.1 機密情報のマスキング

- [ ] **Wrapper**: コマンドライン引数に含まれるパスワード・トークンをマスキング
- [ ] **Wrapper**: コマンド長を制限（最大100文字）
- [ ] **API**: 機密情報がログに記録されていない

**検証コマンド**:
```bash
# マスキングの実装確認
grep -n "password=" wrappers/adminui-processes.sh
grep -n "token=" wrappers/adminui-processes.sh
```

#### 3.2 権限ベースのフィルタリング

- [ ] **API**: 認証ユーザーのみアクセス可能
- [ ] **API**: `read:processes` 権限必須
- [ ] **将来実装**: 一般ユーザーは自分のプロセスのみ閲覧可能

**検証コマンド**:
```bash
# 権限チェックの確認
grep -n 'require_permission("read:processes")' backend/api/routes/processes.py
```

---

### 4. タイムアウト・DoS対策

#### 4.1 タイムアウト設定

- [ ] **sudo_wrapper**: タイムアウト設定（10秒）
- [ ] **API**: 長時間実行を防止

**検証コマンド**:
```bash
# タイムアウト設定の確認
grep -n "timeout=10" backend/core/sudo_wrapper.py
```

#### 4.2 limit 強制

- [ ] **API**: 最大取得件数を 1000 に制限
- [ ] **Wrapper**: limit を検証・強制

**検証コマンド**:
```bash
# limit 上限の確認
grep -n "le=1000" backend/api/routes/processes.py
grep -n "MAX_LIMIT" wrappers/adminui-processes.sh
```

---

### セキュリティレビュー総括

**合格基準**: 全項目 ✅（チェック済み）

**不合格時のアクション**:
1. 該当箇所を特定
2. 修正方針を backend-impl / frontend-impl に通知
3. 修正後に再レビュー

---

## 🧪 テストレビュー（test-designer）

### 1. ユニットテストカバレッジ

#### 1.1 カバレッジ目標

- [ ] **processes.py**: カバレッジ 85% 以上
- [ ] **sudo_wrapper.py**: get_processes() メソッドのカバレッジ 90% 以上

**検証コマンド**:
```bash
pytest tests/test_processes.py --cov=backend/api/routes/processes --cov-report=term
pytest tests/test_processes.py --cov=backend/core/sudo_wrapper --cov-report=html
```

#### 1.2 必須テストケース

**正常系**:
- [ ] デフォルトパラメータでプロセス一覧取得
- [ ] ソート指定（cpu, mem, pid, time）
- [ ] ユーザーフィルタ指定
- [ ] CPU/メモリフィルタ指定
- [ ] 複合フィルタ（ユーザー + CPU + メモリ）

**異常系**:
- [ ] 不正なソートキー（`sort_by=invalid`）
- [ ] 範囲外の limit（`limit=9999`）
- [ ] 範囲外の min_cpu（`min_cpu=200.0`）
- [ ] 不正なユーザー名（特殊文字: `filter_user=root; ls`）
- [ ] allowlist 外のユーザー（`filter_user=hacker`）

**認証・認可**:
- [ ] 認証なし（401 Unauthorized）
- [ ] 権限なし（403 Forbidden）
- [ ] 正常な認証・認可

**検証コマンド**:
```bash
# テストケースの存在確認
grep -n "def test_" tests/test_processes.py | wc -l

# 期待されるテスト数: 15+ 個
```

---

### 2. Wrapper スクリプトのテスト

#### 2.1 Bash テストスクリプト

- [ ] `wrappers/test/test-adminui-processes.sh` が存在
- [ ] 正常系テスト（デフォルト、ソート、フィルタ）
- [ ] 異常系テスト（不正入力、allowlist 拒否、特殊文字）
- [ ] 全テストが自動実行可能
- [ ] テスト結果が明確（PASS/FAIL カウント）

**検証コマンド**:
```bash
cd wrappers/test
bash test-adminui-processes.sh
```

**期待される出力**:
```
✅ PASS: Default parameters
✅ PASS: Sort by mem
✅ PASS: Filter by root user
✅ PASS: Reject invalid sort key
✅ PASS: Reject user not in allowlist
✅ PASS: Reject forbidden characters
✅ PASS: Reject out-of-range limit

==========================================
Test Results:
  PASS: 7
  FAIL: 0
==========================================
✅ All tests passed!
```

---

### 3. セキュリティテスト

#### 3.1 特殊文字インジェクション

- [ ] `;` を含む入力が拒否される
- [ ] `|` を含む入力が拒否される
- [ ] `$` を含む入力が拒否される
- [ ] `` ` `` を含む入力が拒否される

**テストケース例**:
```python
def test_reject_special_chars_semicolon(client, admin_token):
    response = client.get(
        "/api/v1/processes?filter_user=root; rm -rf /",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert response.status_code == 422
```

#### 3.2 allowlist 検証

- [ ] allowlist 外のユーザーが拒否される
- [ ] allowlist 外のソートキーが拒否される

**テストケース例**:
```python
def test_reject_user_not_in_allowlist(client, admin_token):
    response = client.get(
        "/api/v1/processes?filter_user=hacker",
        headers={"Authorization": f"Bearer {admin_token}"},
    )
    assert response.status_code == 403
```

---

### テストレビュー総括

**合格基準**:
- ユニットテストカバレッジ 85% 以上
- Wrapper テスト全通過
- セキュリティテスト全通過

**不合格時のアクション**:
1. 不足しているテストケースを特定
2. test-designer がテストケースを追加
3. 再実行・再レビュー

---

## 🔍 コードレビュー（code-reviewer）

### 1. コーディング規約

#### 1.1 Python

- [ ] **型ヒント**: 全関数に型ヒントが付与されている
- [ ] **docstring**: 全関数に docstring が記載されている（Args, Returns, Raises）
- [ ] **命名規則**: PEP 8 準拠（snake_case, UPPER_CASE）
- [ ] **インポート**: 標準ライブラリ → サードパーティ → ローカル の順
- [ ] **行長**: 最大100文字

**検証コマンド**:
```bash
# flake8 チェック
flake8 backend/api/routes/processes.py --max-line-length=100

# mypy 型チェック
mypy backend/api/routes/processes.py --strict
```

#### 1.2 Bash

- [ ] **shebang**: `#!/bin/bash` が先頭にある
- [ ] **set -euo pipefail**: エラーハンドリング設定
- [ ] **配列使用**: コマンド引数は配列で渡す
- [ ] **引用符**: 変数は `"$VAR"` で引用
- [ ] **関数**: 複雑なロジックは関数化

**検証コマンド**:
```bash
# shellcheck チェック
shellcheck wrappers/adminui-processes.sh
```

---

### 2. エラーハンドリング

#### 2.1 API Route

- [ ] **try-except**: 全エラーケースが処理されている
- [ ] **HTTPException**: 適切なステータスコードを返す
- [ ] **監査ログ**: エラー時も監査ログを記録

**検証コマンド**:
```bash
# エラーハンドリングの確認
grep -n "except" backend/api/routes/processes.py
grep -n "HTTPException" backend/api/routes/processes.py
```

#### 2.2 Wrapper Script

- [ ] **exit 1**: エラー時は非ゼロで終了
- [ ] **logger**: エラー時は logger でログ記録
- [ ] **JSON エラー**: エラー時も JSON 形式で出力

**検証コマンド**:
```bash
# エラーハンドリングの確認
grep -n "exit 1" wrappers/adminui-processes.sh
grep -n "error()" wrappers/adminui-processes.sh
```

---

### 3. パフォーマンス

#### 3.1 効率的なコマンド実行

- [ ] **ps コマンド**: 最小限のオプションで実行
- [ ] **limit 強制**: 大量データを取得しない
- [ ] **タイムアウト**: 長時間実行を防止

#### 3.2 JSON パース

- [ ] **jq 使用**: Bash での JSON 操作は jq を使用
- [ ] **Python**: Pydantic でデータ検証

---

### コードレビュー総括

**合格基準**:
- flake8 エラーなし
- mypy 型エラーなし
- shellcheck エラーなし
- 全エラーケースが処理されている

**不合格時のアクション**:
1. 問題箇所を特定
2. 修正方針を提示
3. 修正後に再レビュー

---

## 🏗️ アーキテクチャレビュー（arch-reviewer）

### 1. 既存パターンとの一貫性

#### 1.1 ファイル配置

- [ ] `backend/api/routes/processes.py` が存在
- [ ] `backend/core/sudo_wrapper.py` に `get_processes()` メソッドが追加
- [ ] `wrappers/adminui-processes.sh` が存在
- [ ] `frontend/processes.html` が存在
- [ ] `frontend/js/processes.js` が存在

**検証コマンド**:
```bash
# ファイルの存在確認
ls -l backend/api/routes/processes.py
ls -l wrappers/adminui-processes.sh
ls -l frontend/processes.html
ls -l frontend/js/processes.js
```

#### 1.2 API 設計

- [ ] **Prefix**: `/api/v1/processes`
- [ ] **Tags**: `tags=["processes"]`
- [ ] **認可**: `require_permission("read:processes")`
- [ ] **レスポンスモデル**: Pydantic で定義

**検証コマンド**:
```bash
# API 設計の確認
grep -n 'prefix="/processes"' backend/api/routes/processes.py
grep -n 'tags=\["processes"\]' backend/api/routes/processes.py
grep -n 'require_permission("read:processes")' backend/api/routes/processes.py
```

---

### 2. 責務分離

#### 2.1 3層アーキテクチャ

- [ ] **Wrapper Script**: システムコマンド実行 + JSON 出力
- [ ] **sudo_wrapper.py**: ラッパー呼び出し + エラーハンドリング
- [ ] **API Route**: 認証・認可 + 監査ログ + レスポンス整形

**検証**:
- Wrapper Script に認証ロジックが含まれていないか？
- API Route にシステムコマンド実行が含まれていないか？

---

### 3. 拡張性

#### 3.1 Phase 2 (操作系) への拡張性

- [ ] **プロセス停止**: 新しいエンドポイント追加が容易か？
- [ ] **承認フロー**: 承認ロジックの追加が容易か？
- [ ] **allowlist 拡張**: 新しいサービス追加が容易か？

**将来の実装**:
```python
# Phase 2: プロセス停止
@router.post("/{pid}/stop")
async def stop_process(
    pid: int,
    current_user: TokenData = Depends(require_permission("execute:process_stop")),
):
    # sudo ラッパー経由でプロセス停止
    result = sudo_wrapper.stop_process(pid)
    # 監査ログ記録
    # ...
```

---

### 4. 保守性

#### 4.1 コードの可読性

- [ ] **関数名**: 明確で理解しやすい
- [ ] **コメント**: 複雑なロジックにコメントがある
- [ ] **マジックナンバー**: 定数化されている

#### 4.2 ドキュメント

- [ ] **設計書**: processes-module-design.md が存在
- [ ] **実装ガイド**: processes-implementation-guide.md が存在
- [ ] **レビューチェックリスト**: 本ドキュメントが存在

---

### アーキテクチャレビュー総括

**合格基準**:
- 既存パターンと一貫性がある
- 責務分離が適切
- 拡張性が高い
- 保守性が高い

**不合格時のアクション**:
1. 設計の問題点を特定
2. リファクタリング方針を提示
3. 再設計・再実装

---

## 📊 レビュー総合判定

### 合格基準

| レビュー項目 | 担当 | 合格基準 |
|------------|------|---------|
| **セキュリティレビュー** | security-checker | 全項目 ✅ |
| **テストレビュー** | test-designer | カバレッジ 85% 以上、全テスト通過 |
| **コードレビュー** | code-reviewer | flake8, mypy, shellcheck エラーなし |
| **アーキテクチャレビュー** | arch-reviewer | 既存パターン一貫性、拡張性、保守性 |

### 最終承認フロー

```
security-checker ──┐
test-designer ─────┤
code-reviewer ─────┼──→ team-lead (最終承認) ──→ Git Commit
arch-reviewer ─────┘
```

### 不合格時のアクション

1. **問題点の特定**: 各レビュアーが具体的な問題箇所を指摘
2. **修正方針の提示**: backend-impl / frontend-impl に修正内容を通知
3. **修正実装**: 該当チームが修正
4. **再レビュー**: 全レビュアーが再確認
5. **最終承認**: team-lead が承認

---

## 🎯 レビュー実施手順

### 1. 各レビュアーの実施タイミング

```
実装完了
  ↓
security-checker: セキュリティレビュー（並列実行）
test-designer: テストレビュー（並列実行）
code-reviewer: コードレビュー（並列実行）
  ↓
arch-reviewer: アーキテクチャレビュー（統合レビュー）
  ↓
team-lead: 最終承認
```

### 2. レビューコメントの記載場所

**ファイル**: `docs/architecture/processes-review-comments.md`

```markdown
# Running Processes モジュール レビューコメント

## セキュリティレビュー（security-checker）

### 指摘事項
- [ ] 問題1: 説明
- [ ] 問題2: 説明

### 承認
- [ ] セキュリティレビュー合格

---

## テストレビュー（test-designer）

### 指摘事項
- [ ] 問題1: 説明

### 承認
- [ ] テストレビュー合格

---

## コードレビュー（code-reviewer）

### 指摘事項
- [ ] 問題1: 説明

### 承認
- [ ] コードレビュー合格

---

## アーキテクチャレビュー（arch-reviewer）

### 指摘事項
- [ ] 問題1: 説明

### 承認
- [ ] アーキテクチャレビュー合格

---

## 最終承認（team-lead）

- [ ] 全レビューが合格
- [ ] Git Commit 承認
```

---

## 📝 まとめ

本チェックリストを使用して、Running Processes モジュールの実装品質を確保してください。

**重要ポイント**:
1. **セキュリティファースト**: CLAUDE.md の原則を厳守
2. **既存パターン継承**: 一貫性のある実装
3. **多層防御**: Frontend → API → Wrapper での多重検証
4. **監査証跡**: 全操作を記録
5. **テスト充実**: カバレッジ 85% 以上

**次のステップ**:
- backend-impl, frontend-impl が実装完了
- 各レビュアーがこのチェックリストに基づいてレビュー
- team-lead が最終承認
- Git commit & Push

---

**参照**:
- [processes-module-design.md](./processes-module-design.md) - 詳細設計書
- [processes-implementation-guide.md](./processes-implementation-guide.md) - 実装ガイド
- [CLAUDE.md](/mnt/LinuxHDD/Linux-Management-Systm/CLAUDE.md) - セキュリティ原則

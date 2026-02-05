"""
セキュリティテスト

CLAUDE.md のセキュリティ原則を検証
"""

import subprocess
from pathlib import Path

import pytest


class TestSecurityPrinciples:
    """セキュリティ原則の検証"""

    @pytest.fixture(scope="class")
    def project_root(self):
        """プロジェクトルート"""
        return Path(__file__).parent.parent.parent

    def test_no_shell_true_in_backend(self, project_root):
        """backend/ に shell=True が存在しないこと（コメント除く）"""
        backend_dir = project_root / "backend"

        # Python ファイルのみを対象、コメント行を除外
        result = subprocess.run(
            ["grep", "-r", "--include=*.py", "shell=True", str(backend_dir)],
            capture_output=True,
            text=True,
        )

        if result.returncode == 0:
            # 検出された行を解析
            lines = result.stdout.strip().split('\n')
            violations = []

            for line in lines:
                # ファイルパス:コンテンツ の形式
                if ':' not in line:
                    continue

                parts = line.split(':', 1)
                if len(parts) < 2:
                    continue

                content = parts[1].strip()

                # コメント行をスキップ
                if content.startswith('#'):
                    continue

                # 実際の違反
                violations.append(line)

            # 違反がある場合は失敗
            if violations:
                assert False, f"shell=True が検出されました（CRITICAL VIOLATION）\n" + '\n'.join(violations)

    def test_no_os_system_in_backend(self, project_root):
        """backend/ に os.system が存在しないこと"""
        backend_dir = project_root / "backend"

        result = subprocess.run(
            ["grep", "-rE", r"os\.system\s*\(", str(backend_dir)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, "os.system が検出されました（CRITICAL VIOLATION）"

    def test_no_eval_exec_in_backend(self, project_root):
        """backend/ に eval/exec が存在しないこと"""
        backend_dir = project_root / "backend"

        result = subprocess.run(
            ["grep", "-rE", r"\b(eval|exec)\s*\(", str(backend_dir)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, "eval/exec が検出されました（CRITICAL VIOLATION）"

    def test_no_bash_c_in_wrappers(self, project_root):
        """wrappers/ に bash -c が存在しないこと"""
        wrappers_dir = project_root / "wrappers"

        # adminui-*.sh のみを対象（test/ と README.md を除外）
        result = subprocess.run(
            ["grep", "-r", "--include=adminui-*.sh", "bash -c", str(wrappers_dir)],
            capture_output=True,
            text=True,
        )

        assert result.returncode != 0, f"bash -c が検出されました（CRITICAL VIOLATION）\n{result.stdout}"


class TestInputValidation:
    """入力検証テスト"""

    def test_reject_command_injection_in_service_name(self, test_client, auth_headers):
        """サービス名にコマンドインジェクションを試行"""
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx; rm -rf /"},
            headers=auth_headers,
        )

        # Pydantic の検証で拒否されるはず
        assert response.status_code == 422  # Unprocessable Entity

    def test_reject_pipe_in_service_name(self, test_client, auth_headers):
        """サービス名にパイプを含める"""
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx|ls"},
            headers=auth_headers,
        )

        assert response.status_code == 422

    def test_reject_command_substitution(self, test_client, auth_headers):
        """サービス名にコマンド置換を含める"""
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx$(whoami)"},
            headers=auth_headers,
        )

        assert response.status_code == 422

    def test_reject_too_long_service_name(self, test_client, auth_headers):
        """サービス名が長すぎる場合"""
        long_name = "a" * 100

        response = test_client.post(
            "/api/services/restart",
            json={"service_name": long_name},
            headers=auth_headers,
        )

        assert response.status_code == 422


class TestAllowlist:
    """allowlist 検証テスト"""

    def test_allowed_service_nginx(self, test_client, auth_headers):
        """許可されたサービス（nginx）"""
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx"},
            headers=auth_headers,
        )

        # 権限チェックは通過（sudo ラッパーの結果は問わない）
        assert response.status_code != 422  # 入力検証エラーではない

    def test_disallowed_service(self, test_client, auth_headers):
        """許可されていないサービス"""
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "malicious-service"},
            headers=auth_headers,
        )

        # sudo ラッパーで拒否されるはず（403 または 500）
        # 入力検証は通過（形式は正しいため）
        assert response.status_code in [403, 500]


class TestAuditLogging:
    """監査ログテスト"""

    def test_audit_log_on_login(self, test_client):
        """ログイン時に監査ログが記録されること"""
        # ログイン
        response = test_client.post(
            "/api/auth/login",
            json={"email": "operator@example.com", "password": "operator123"},
        )

        assert response.status_code == 200

        # TODO: 監査ログファイルを確認
        # audit_log_file = Path("logs/dev/audit/audit_*.json")
        # assert audit_log_file.exists()

    def test_audit_log_on_failed_login(self, test_client):
        """ログイン失敗時にも監査ログが記録されること"""
        response = test_client.post(
            "/api/auth/login",
            json={"email": "operator@example.com", "password": "wrongpassword"},
        )

        assert response.status_code == 401

        # TODO: 監査ログに失敗が記録されていることを確認

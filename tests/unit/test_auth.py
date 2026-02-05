"""
認証・認可のユニットテスト
"""

import pytest


class TestAuthentication:
    """認証テスト"""

    def test_login_success(self, test_client):
        """ログイン成功"""
        response = test_client.post(
            "/api/auth/login",
            json={"email": "operator@example.com", "password": "operator123"},
        )

        assert response.status_code == 200
        data = response.json()
        assert "access_token" in data
        assert data["token_type"] == "bearer"
        assert data["username"] == "operator"
        assert data["role"] == "Operator"

    def test_login_invalid_email(self, test_client):
        """ログイン失敗: 存在しないメールアドレス"""
        response = test_client.post(
            "/api/auth/login",
            json={"email": "nonexistent@example.com", "password": "password123"},
        )

        assert response.status_code == 401
        data = response.json()
        assert data["status"] == "error"

    def test_login_invalid_password(self, test_client):
        """ログイン失敗: 不正なパスワード"""
        response = test_client.post(
            "/api/auth/login",
            json={"email": "operator@example.com", "password": "wrongpassword"},
        )

        assert response.status_code == 401

    def test_get_current_user(self, test_client, auth_headers):
        """現在のユーザー情報取得"""
        response = test_client.get("/api/auth/me", headers=auth_headers)

        assert response.status_code == 200
        data = response.json()
        assert data["username"] == "operator"
        assert data["role"] == "Operator"
        assert "execute:service_restart" in data["permissions"]

    def test_unauthorized_access(self, test_client):
        """認証なしでのアクセス拒否"""
        response = test_client.get("/api/auth/me")

        assert response.status_code == 403  # Forbidden (no Bearer token)


class TestAuthorization:
    """認可テスト"""

    def test_viewer_cannot_restart_service(self, test_client, viewer_token):
        """Viewer はサービス再起動不可"""
        headers = {"Authorization": f"Bearer {viewer_token}"}

        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx"},
            headers=headers,
        )

        assert response.status_code == 403  # Forbidden

    def test_operator_can_restart_service(self, test_client, auth_token):
        """Operator はサービス再起動可能"""
        headers = {"Authorization": f"Bearer {auth_token}"}

        # 注意: 実際の再起動は sudo が必要なため、このテストでは権限チェックのみ
        response = test_client.post(
            "/api/services/restart",
            json={"service_name": "nginx"},
            headers=headers,
        )

        # 権限チェックは通過するが、sudo ラッパーの実行で失敗する可能性がある
        # ステータスコードが 403 でなければ OK
        assert response.status_code != 403

    def test_viewer_can_view_status(self, test_client, viewer_token):
        """Viewer はシステム状態閲覧可能"""
        headers = {"Authorization": f"Bearer {viewer_token}"}

        response = test_client.get("/api/system/status", headers=headers)

        # 権限チェックは通過（sudo ラッパーの実行結果は問わない）
        assert response.status_code != 403

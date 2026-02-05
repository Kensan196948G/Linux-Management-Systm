# Backend - FastAPI REST API

**セキュリティファースト設計の Linux 管理 WebUI バックエンド**

---

## 📋 概要

FastAPI ベースの REST API サーバー。sudo ラッパー経由での安全な Linux 操作を提供。

---

## 📂 構成

```
backend/
├── api/
│   ├── main.py                    # FastAPI アプリケーションエントリーポイント
│   └── routes/
│       ├── auth.py                # 認証エンドポイント（/api/auth/*）
│       ├── system.py              # システム状態（/api/system/*）
│       ├── services.py            # サービス操作（/api/services/*）
│       └── logs.py                # ログ閲覧（/api/logs/*）
│
├── core/
│   ├── config.py                  # 設定管理
│   ├── auth.py                    # 認証・認可
│   ├── audit_log.py               # 監査ログ
│   └── sudo_wrapper.py            # sudo ラッパー呼び出し
│
├── requirements.txt               # 本番依存関係
└── requirements-dev.txt           # 開発・テスト依存関係
```

---

## 🚀 クイックスタート

### 1. セットアップ

```bash
# 開発環境のセットアップ
./scripts/setup/setup-dev-env.sh

# または手動で
python3 -m venv venv
source venv/bin/activate
pip install -r backend/requirements.txt
```

### 2. 開発サーバー起動

```bash
# 簡単な方法
./scripts/start-dev-server.sh

# または手動で
source venv/bin/activate
export ENV=dev
uvicorn backend.api.main:app --host 0.0.0.0 --port 3000 --reload
```

### 3. アクセス

- **HTTP**: http://localhost:3000
- **API ドキュメント**: http://localhost:3000/api/docs
- **ReDoc**: http://localhost:3000/api/redoc

---

## 🔐 認証・認可

### ユーザーロール

| ロール | 権限 |
|--------|------|
| **Viewer** | システム状態閲覧、ログ閲覧 |
| **Operator** | Viewer + サービス再起動 |
| **Approver** | Operator + 危険操作承認 |
| **Admin** | Approver + ユーザー管理、設定管理 |

### デモユーザー（開発環境のみ）

| Email | Password | Role |
|-------|----------|------|
| viewer@example.com | viewer123 | Viewer |
| operator@example.com | operator123 | Operator |
| admin@example.com | admin123 | Admin |

### ログイン方法

```bash
# ログイン
curl -X POST http://localhost:3000/api/auth/login \
  -H "Content-Type: application/json" \
  -d '{"email": "operator@example.com", "password": "operator123"}'

# レスポンス:
# {"access_token": "eyJ...", "token_type": "bearer", ...}

# API 呼び出し（トークン使用）
curl -X GET http://localhost:3000/api/system/status \
  -H "Authorization: Bearer eyJ..."
```

---

## 📡 API エンドポイント

### 認証（/api/auth）

| Method | Endpoint | 説明 | 権限 |
|--------|----------|------|------|
| POST | `/auth/login` | ログイン | - |
| GET | `/auth/me` | 現在のユーザー情報 | 認証必須 |
| POST | `/auth/logout` | ログアウト | 認証必須 |

### システム（/api/system）

| Method | Endpoint | 説明 | 権限 |
|--------|----------|------|------|
| GET | `/system/status` | システム状態取得 | read:status |

### サービス（/api/services）

| Method | Endpoint | 説明 | 権限 |
|--------|----------|------|------|
| POST | `/services/restart` | サービス再起動 | execute:service_restart |

### ログ（/api/logs）

| Method | Endpoint | 説明 | 権限 |
|--------|----------|------|------|
| GET | `/logs/{service_name}` | ログ取得 | read:logs |

---

## 🛡️ セキュリティ実装

### 1. shell=True 禁止（厳守）

```python
# ✅ 正しい実装
subprocess.run(["sudo", wrapper_path, service_name], check=True)

# ❌ 絶対禁止
subprocess.run(f"sudo {wrapper_path} {service_name}", shell=True)
```

### 2. sudo ラッパー経由のみ

```python
# ✅ 正しい実装
sudo_wrapper.restart_service("nginx")

# ❌ 直接実行禁止
subprocess.run(["sudo", "systemctl", "restart", "nginx"])
```

### 3. 全操作の監査ログ

```python
# 試行時
audit_log.record("service_restart", user_id, "nginx", "attempt")

# 成功時
audit_log.record("service_restart", user_id, "nginx", "success")

# 失敗時
audit_log.record("service_restart", user_id, "nginx", "failure", {"error": str(e)})
```

### 4. JWT ベースの認証

- HS256 アルゴリズム
- 有効期限: 60分
- 権限ベースのアクセス制御

---

## 🧪 テスト

```bash
# 全テスト実行
pytest backend/tests/ -v

# カバレッジ付き
pytest backend/tests/ -v --cov=backend --cov-report=html

# セキュリティスキャン
bandit -r backend/ -ll
```

---

## 📚 参考資料

- [../CLAUDE.md](../CLAUDE.md) - セキュリティ原則
- [../config/dev.json](../config/dev.json) - 開発環境設定
- [../docs/sudoers-config.md](../docs/sudoers-config.md) - sudoers 設定

---

**最終更新**: 2026-02-05

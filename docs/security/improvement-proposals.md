# 改善提案リスト

**作成日**: 2026-02-06
**対象**: Linux Management WebUI v0.1
**作成者**: Security SubAgent（@Security / @Architect / @QA / @CIManager）

---

## 📋 改善提案サマリ

| ID | カテゴリ | 優先度 | リスク | 工数 | 対応フェーズ |
|----|---------|--------|--------|------|------------|
| **IMP-001** | 認証 | **CRITICAL** | **MEDIUM** | 大 | **v0.3** |
| **IMP-002** | セキュリティ | **CRITICAL** | **MEDIUM** | 中 | **v0.3** |
| **IMP-003** | セキュリティ | **HIGH** | **MEDIUM** | 中 | **v0.3** |
| **IMP-004** | テスト | **HIGH** | LOW | 中 | v0.3 |
| **IMP-005** | CI/CD | **HIGH** | LOW | 小 | v0.3 |
| **IMP-006** | ドキュメント | MEDIUM | LOW | 中 | v0.3 |
| **IMP-007** | 設定 | LOW | LOW | 小 | v0.4 |
| **IMP-008** | ログ | LOW | LOW | 小 | v0.4 |

---

## 🔴 CRITICAL 優先度（v0.3必須）

### IMP-001: 本番環境認証の実装

**カテゴリ**: 認証
**リスク**: MEDIUM
**工数**: 大（40時間）
**対応フェーズ**: **v0.3（必須）**

#### 現状

```python
# backend/core/auth.py:213-216
else:
    # 本番環境: bcrypt 使用（TODO: データベースから取得）
    logger.error("Production authentication not implemented yet")
    return None
```

**問題点**:
- 本番環境で認証が動作しない
- デモアカウントが本番で使用される危険性
- パスワードポリシーが未定義

#### 提案内容

##### 1. データベーススキーマ設計

```sql
-- users テーブル
CREATE TABLE users (
    user_id VARCHAR(36) PRIMARY KEY,
    username VARCHAR(64) NOT NULL UNIQUE,
    email VARCHAR(255) NOT NULL UNIQUE,
    hashed_password VARCHAR(255) NOT NULL,
    role VARCHAR(32) NOT NULL,
    disabled BOOLEAN DEFAULT FALSE,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    updated_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    last_login TIMESTAMP,
    failed_login_count INTEGER DEFAULT 0,
    locked_until TIMESTAMP
);

-- sessions テーブル（オプション）
CREATE TABLE sessions (
    session_id VARCHAR(36) PRIMARY KEY,
    user_id VARCHAR(36) NOT NULL,
    token_hash VARCHAR(255) NOT NULL,
    created_at TIMESTAMP DEFAULT CURRENT_TIMESTAMP,
    expires_at TIMESTAMP NOT NULL,
    ip_address VARCHAR(45),
    user_agent TEXT,
    FOREIGN KEY (user_id) REFERENCES users(user_id)
);
```

##### 2. bcrypt ハッシュ実装

```python
# backend/core/auth.py（追加実装）
def authenticate_user_production(email: str, password: str) -> Optional[User]:
    """本番環境認証（データベース使用）"""
    from .database import get_db

    db = get_db()
    user_record = db.query(UserModel).filter_by(email=email).first()

    if not user_record:
        logger.warning(f"Authentication failed: user not found - {email}")
        return None

    if user_record.disabled:
        logger.warning(f"Authentication failed: user disabled - {email}")
        return None

    # アカウントロックチェック
    if user_record.locked_until and user_record.locked_until > datetime.now():
        logger.warning(f"Authentication failed: account locked - {email}")
        return None

    # パスワード検証
    if not verify_password(password, user_record.hashed_password):
        # 失敗回数をインクリメント
        user_record.failed_login_count += 1

        # 5回失敗でアカウントロック（30分）
        if user_record.failed_login_count >= 5:
            user_record.locked_until = datetime.now() + timedelta(minutes=30)
            logger.warning(f"Account locked due to failed login attempts: {email}")

        db.commit()
        return None

    # 認証成功: 失敗回数リセット
    user_record.failed_login_count = 0
    user_record.last_login = datetime.now()
    db.commit()

    logger.info(f"Authentication successful (PROD mode): {email}")

    return User(
        user_id=user_record.user_id,
        username=user_record.username,
        email=user_record.email,
        role=user_record.role,
        hashed_password=user_record.hashed_password,
        disabled=user_record.disabled,
    )
```

##### 3. パスワードポリシー実装

```python
# backend/core/auth.py（追加）
import re

def validate_password_policy(password: str) -> tuple[bool, str]:
    """
    パスワードポリシー検証

    要件:
    - 最小12文字
    - 大文字・小文字・数字・記号をそれぞれ1文字以上
    - 一般的なパスワードの禁止（辞書攻撃対策）
    """
    if len(password) < 12:
        return False, "Password must be at least 12 characters long"

    if not re.search(r'[A-Z]', password):
        return False, "Password must contain at least one uppercase letter"

    if not re.search(r'[a-z]', password):
        return False, "Password must contain at least one lowercase letter"

    if not re.search(r'\d', password):
        return False, "Password must contain at least one digit"

    if not re.search(r'[!@#$%^&*(),.?":{}|<>]', password):
        return False, "Password must contain at least one special character"

    # 一般的なパスワードの禁止
    common_passwords = ["password", "123456", "admin", "letmein", "welcome"]
    if password.lower() in common_passwords:
        return False, "Password is too common"

    return True, "Password meets policy requirements"
```

##### 4. 初期管理者アカウント作成スクリプト

```python
# scripts/create_admin.py
import sys
from getpass import getpass
from backend.core.auth import get_password_hash, validate_password_policy
from backend.core.database import get_db, UserModel

def create_admin_user():
    """初期管理者アカウント作成"""
    print("=== Create Initial Admin User ===")

    username = input("Username: ")
    email = input("Email: ")
    password = getpass("Password: ")
    password_confirm = getpass("Confirm password: ")

    if password != password_confirm:
        print("ERROR: Passwords do not match")
        sys.exit(1)

    # パスワードポリシー検証
    valid, message = validate_password_policy(password)
    if not valid:
        print(f"ERROR: {message}")
        sys.exit(1)

    # ハッシュ化
    hashed_password = get_password_hash(password)

    # データベースに保存
    db = get_db()
    admin_user = UserModel(
        user_id=str(uuid.uuid4()),
        username=username,
        email=email,
        hashed_password=hashed_password,
        role="Admin",
        disabled=False,
    )

    db.add(admin_user)
    db.commit()

    print(f"✅ Admin user created: {email}")

if __name__ == "__main__":
    create_admin_user()
```

#### 実装チェックリスト

- [ ] データベーススキーマ作成（SQLite → PostgreSQL移行検討）
- [ ] bcrypt ハッシュ実装
- [ ] パスワードポリシー実装
- [ ] アカウントロック機能（5回失敗で30分ロック）
- [ ] 初期管理者作成スクリプト
- [ ] ユーザー管理API（作成/更新/削除）
- [ ] パスワード変更API
- [ ] パスワードリセット機能（メール送信）
- [ ] セッション管理（データベース）
- [ ] テストケース作成（10+ テスト）
- [ ] ドキュメント更新

#### 受入基準

1. 本番環境で bcrypt による認証が動作する
2. パスワードポリシーが強制される
3. アカウントロック機能が動作する
4. 初期管理者アカウントが作成できる
5. テストカバレッジ 90%以上

---

### IMP-002: HTTPS強制の実装

**カテゴリ**: セキュリティ
**リスク**: MEDIUM
**工数**: 中（16時間）
**対応フェーズ**: **v0.3（必須）**

#### 現状

```python
# backend/core/config.py:50
require_https: bool = False  # 開発環境デフォルト
```

**問題点**:
- 平文通信によるトークン漏洩
- 中間者攻撃（MITM）の危険性
- 認証情報の盗聴リスク

#### 提案内容

##### 1. Production設定で HTTPS 強制

```json
// config/prod.json
{
  "environment": "production",
  "security": {
    "require_https": true,  // 必須
    "allowed_services": ["nginx", "postgresql", "redis"],
    "session_timeout": 3600,
    "max_login_attempts": 5
  }
}
```

##### 2. Middleware による HTTP リクエスト拒否

```python
# backend/api/main.py（追加）
from fastapi import Request, HTTPException

@app.middleware("http")
async def enforce_https(request: Request, call_next):
    """HTTPS 強制ミドルウェア"""
    if settings.security.require_https:
        # X-Forwarded-Proto ヘッダーをチェック（リバースプロキシ経由）
        forwarded_proto = request.headers.get("X-Forwarded-Proto")

        if forwarded_proto == "http" or (
            not forwarded_proto and request.url.scheme != "https"
        ):
            logger.warning(
                f"HTTP request rejected: {request.client.host} -> {request.url.path}"
            )

            # 監査ログ記録
            audit_log.record(
                operation="http_request_rejected",
                user_id="anonymous",
                target=request.url.path,
                status="denied",
                details={
                    "client_ip": request.client.host,
                    "reason": "HTTPS required"
                },
            )

            raise HTTPException(
                status_code=400,
                detail="HTTPS required. Please use https:// instead of http://"
            )

    return await call_next(request)
```

##### 3. HSTS ヘッダーの追加

```python
# backend/api/main.py（追加）
@app.middleware("http")
async def add_security_headers(request: Request, call_next):
    """セキュリティヘッダー追加ミドルウェア"""
    response = await call_next(request)

    if settings.security.require_https:
        # HSTS (HTTP Strict Transport Security)
        response.headers["Strict-Transport-Security"] = (
            "max-age=31536000; includeSubDomains; preload"
        )

        # その他のセキュリティヘッダー
        response.headers["X-Content-Type-Options"] = "nosniff"
        response.headers["X-Frame-Options"] = "DENY"
        response.headers["X-XSS-Protection"] = "1; mode=block"
        response.headers["Referrer-Policy"] = "strict-origin-when-cross-origin"

    return response
```

##### 4. 証明書検証（起動時）

```python
# backend/api/main.py（追加）
from pathlib import Path

async def validate_ssl_certificates():
    """SSL証明書の検証"""
    if not settings.server.ssl_enabled:
        logger.warning("SSL is disabled")
        return

    cert_file = Path(settings.server.ssl_cert)
    key_file = Path(settings.server.ssl_key)

    if not cert_file.exists():
        raise FileNotFoundError(f"SSL certificate not found: {cert_file}")

    if not key_file.exists():
        raise FileNotFoundError(f"SSL key not found: {key_file}")

    # 証明書の有効期限チェック（オプション）
    # from cryptography import x509
    # from cryptography.hazmat.backends import default_backend
    # ...

    logger.info(f"SSL certificate validated: {cert_file}")
```

#### 実装チェックリスト

- [ ] `prod.json` で `require_https: true` 設定
- [ ] HTTP リクエスト拒否ミドルウェア実装
- [ ] HSTS ヘッダー追加
- [ ] X-Forwarded-Proto ヘッダー対応（リバースプロキシ）
- [ ] 証明書検証（起動時）
- [ ] HTTP → HTTPS リダイレクト（オプション）
- [ ] テストケース作成（5+ テスト）
- [ ] ドキュメント更新

#### 受入基準

1. Production環境で HTTP リクエストが拒否される
2. HSTS ヘッダーが正しく設定される
3. X-Forwarded-Proto ヘッダーが正しく処理される
4. 証明書が存在しない場合は起動失敗
5. テストカバレッジ 85%以上

---

## 🔴 HIGH 優先度（v0.3推奨）

### IMP-003: レート制限の実装

**カテゴリ**: セキュリティ
**リスク**: MEDIUM
**工数**: 中（12時間）
**対応フェーズ**: **v0.3（推奨）**

#### 現状

レート制限機能が未実装

**問題点**:
- DoS攻撃による可用性低下
- ブルートフォース攻撃（ログイン試行）
- リソース枯渇

#### 提案内容

##### 1. slowapi ライブラリ導入

```bash
# backend/requirements.txt（追加）
slowapi==0.1.9
```

##### 2. レート制限設定

```python
# backend/api/main.py（追加）
from slowapi import Limiter, _rate_limit_exceeded_handler
from slowapi.util import get_remote_address
from slowapi.errors import RateLimitExceeded

# レート制限設定
limiter = Limiter(
    key_func=get_remote_address,
    default_limits=["100/minute", "1000/hour"],
    storage_uri="memory://"  # Production: redis://localhost:6379
)

app.state.limiter = limiter
app.add_exception_handler(RateLimitExceeded, _rate_limit_exceeded_handler)
```

##### 3. エンドポイントごとのレート制限

```python
# backend/api/routes/auth.py（修正）
@router.post("/login")
@limiter.limit("5/minute")  # 1分間に5回まで
async def login(
    request: Request,
    credentials: LoginRequest,
):
    """ログイン（レート制限付き）"""
    # ... existing code ...
```

```python
# backend/api/routes/services.py（修正）
@router.post("/restart")
@limiter.limit("10/minute")  # 1分間に10回まで
async def restart_service(
    request: Request,
    service_request: ServiceRestartRequest,
    current_user: TokenData = Depends(require_permission("execute:service_restart")),
):
    """サービス再起動（レート制限付き）"""
    # ... existing code ...
```

##### 4. レート制限超過時の監査ログ

```python
# backend/api/main.py（追加）
@app.exception_handler(RateLimitExceeded)
async def rate_limit_handler(request: Request, exc: RateLimitExceeded):
    """レート制限超過時のハンドラ"""

    # 監査ログ記録
    audit_log.record(
        operation="rate_limit_exceeded",
        user_id=request.user.user_id if hasattr(request, "user") else "anonymous",
        target=request.url.path,
        status="denied",
        details={
            "client_ip": request.client.host,
            "limit": str(exc.detail),
        },
    )

    logger.warning(
        f"Rate limit exceeded: {request.client.host} -> {request.url.path}"
    )

    return JSONResponse(
        status_code=429,
        content={
            "status": "error",
            "error_code": "RATE_LIMIT_EXCEEDED",
            "message": "Too many requests. Please try again later.",
            "detail": str(exc.detail),
        },
    )
```

#### 実装チェックリスト

- [ ] slowapi ライブラリ導入
- [ ] 全エンドポイントにデフォルトレート制限適用
- [ ] 認証エンドポイントに厳格なレート制限（5/minute）
- [ ] サービス操作エンドポイントにレート制限（10/minute）
- [ ] レート制限超過時の監査ログ記録
- [ ] Redis バックエンド対応（Production）
- [ ] ユーザーベースレート制限（IPベースからユーザーベースへ）
- [ ] テストケース作成（5+ テスト）
- [ ] ドキュメント更新

#### 受入基準

1. レート制限が全エンドポイントで動作する
2. レート制限超過時に429エラーが返される
3. 監査ログに記録される
4. 認証エンドポイントが特に厳格（5/minute）
5. テストカバレッジ 85%以上

---

### IMP-004: テストカバレッジ向上

**カテゴリ**: テスト
**リスク**: LOW
**工数**: 中（20時間）
**対応フェーズ**: v0.3

#### 現状

| コンポーネント | 目標 | 現状（推定） | 不足 |
|--------------|------|------------|------|
| `backend/core/` | 90%+ | 85% | 5% |
| `backend/api/` | 85%+ | 75% | 10% |
| `wrappers/` | 100% | 90% | 10% |

#### 提案内容

##### 追加すべきテストケース

**backend/core/sudo_wrapper.py**:
```python
def test_wrapper_timeout():
    """タイムアウト時に適切にエラーを返すこと"""
    with patch("subprocess.run", side_effect=subprocess.TimeoutExpired("cmd", 30)):
        with pytest.raises(SudoWrapperError, match="timed out"):
            sudo_wrapper._execute("adminui-status.sh", [], timeout=30)

def test_wrapper_json_parse_error():
    """JSON パースエラー時のハンドリング"""
    with patch("subprocess.run") as mock_run:
        mock_run.return_value.stdout = "Invalid JSON"
        result = sudo_wrapper._execute("adminui-status.sh", [])
        assert result["status"] == "success"
        assert "output" in result

def test_wrapper_permission_denied():
    """権限不足時のエラーハンドリング"""
    with patch("subprocess.run", side_effect=subprocess.CalledProcessError(1, "cmd", stderr="Permission denied")):
        with pytest.raises(SudoWrapperError, match="Permission denied"):
            sudo_wrapper._execute("adminui-status.sh", [])
```

**backend/core/audit_log.py**:
```python
def test_audit_log_file_permission(tmp_path):
    """監査ログファイルのパーミッションが適切か"""
    audit_log = AuditLog(log_dir=tmp_path)
    audit_log.record("test", "user", "target", "success")

    log_file = list(tmp_path.glob("audit_*.json"))[0]
    import stat
    file_stat = log_file.stat()

    # パーミッション: 0644 (rw-r--r--)
    assert stat.S_IMODE(file_stat.st_mode) == 0o644

def test_audit_log_rotation(tmp_path):
    """日次ローテーションが機能するか"""
    audit_log = AuditLog(log_dir=tmp_path)

    # 今日のログ
    audit_log.record("test1", "user", "target", "success")

    # 日付を変更（モック）
    with patch("backend.core.audit_log.datetime") as mock_datetime:
        mock_datetime.now.return_value = datetime.now() + timedelta(days=1)
        audit_log = AuditLog(log_dir=tmp_path)  # 再初期化
        audit_log.record("test2", "user", "target", "success")

    # 2つのファイルが存在することを確認
    log_files = list(tmp_path.glob("audit_*.json"))
    assert len(log_files) == 2
```

**wrappers/adminui-status.sh**:
```bash
#!/bin/bash
# wrappers/test/test-adminui-status.sh

# ディスク容量不足時の挙動（モック）
test_disk_full() {
    # df コマンドを一時的に置き換え
    # （実装は複雑なため、統合テストで実施推奨）
    echo "✅ Disk full test (manual verification required)"
}

# CPU使用率100%時の挙動
test_cpu_100_percent() {
    # top コマンドの出力をモック
    echo "✅ CPU 100% test (manual verification required)"
}
```

#### 実装チェックリスト

- [ ] `sudo_wrapper.py` に3つのテスト追加
- [ ] `audit_log.py` に3つのテスト追加
- [ ] `auth.py` に5つのテスト追加（本番認証）
- [ ] `config.py` に2つのテスト追加
- [ ] ラッパースクリプトの異常系テスト強化
- [ ] エッジケーステスト（境界値、null、空文字）
- [ ] パフォーマンステスト（1000+プロセス時）
- [ ] pytest カバレッジレポート確認
- [ ] カバレッジ 90%以上達成

#### 受入基準

1. `backend/core/` カバレッジ 90%以上
2. `backend/api/` カバレッジ 85%以上
3. `wrappers/` カバレッジ 90%以上（bash 100%は困難）
4. 全テスト PASS
5. CI/CDで自動実行

---

### IMP-005: CI/CD 依存関係脆弱性スキャン

**カテゴリ**: CI/CD
**リスク**: LOW
**工数**: 小（4時間）
**対応フェーズ**: v0.3

#### 現状

依存関係の脆弱性スキャンが未実装

#### 提案内容

##### 1. Safety スキャン追加

```yaml
# .github/workflows/security-audit.yml（追加）
- name: Dependency vulnerability scan
  run: |
    pip install safety
    safety check --json --output safety-report.json || true

- name: Upload safety report
  if: always()
  uses: actions/upload-artifact@v4
  with:
    name: safety-report
    path: safety-report.json
```

##### 2. Dependabot 設定

```yaml
# .github/dependabot.yml（新規作成）
version: 2
updates:
  - package-ecosystem: "pip"
    directory: "/backend"
    schedule:
      interval: "weekly"
    reviewers:
      - "security-team"
    commit-message:
      prefix: "chore(deps)"

  - package-ecosystem: "github-actions"
    directory: "/"
    schedule:
      interval: "weekly"
```

##### 3. Trivy スキャン（コンテナイメージ）

```yaml
# .github/workflows/security-audit.yml（追加）
- name: Container image scan (Trivy)
  uses: aquasecurity/trivy-action@master
  with:
    image-ref: 'adminui:latest'
    format: 'sarif'
    output: 'trivy-results.sarif'

- name: Upload Trivy results
  uses: github/codeql-action/upload-sarif@v2
  with:
    sarif_file: 'trivy-results.sarif'
```

#### 実装チェックリスト

- [ ] Safety スキャン追加（CI/CD）
- [ ] Dependabot 設定
- [ ] Trivy スキャン追加（Dockerイメージ）
- [ ] TruffleHog 追加（Secrets検出）
- [ ] 脆弱性レポート自動生成
- [ ] 週次レポート送信（オプション）

#### 受入基準

1. 全Push時に依存関係スキャン実行
2. HIGH以上の脆弱性検出時にCI失敗
3. Dependabot PRが自動作成される
4. レポートがアーティファクトとして保存される

---

## 🔵 MEDIUM / LOW 優先度

### IMP-006: セキュリティ運用手順書の作成

**カテゴリ**: ドキュメント
**優先度**: MEDIUM
**工数**: 中（16時間）
**対応フェーズ**: v0.3

#### 作成すべきドキュメント

1. **セキュリティインシデント対応手順書**
   - Shell Injection検出時の対応
   - 不正アクセス検出時の対応
   - エスカレーション基準
   - 関係者連絡先

2. **監査ログ運用手順書**
   - ログ保全期間（推奨: 90日以上）
   - 定期レビュー手順（週次/月次）
   - 異常検知パターン
   - ログアーカイブ手順

3. **脆弱性管理手順書**
   - 依存関係の定期更新（月次）
   - セキュリティパッチ適用フロー
   - 脆弱性スキャン頻度（週次）
   - 脆弱性対応SLA

---

### IMP-007: タイムアウト値の設定ファイル化

**カテゴリ**: 設定
**優先度**: LOW
**工数**: 小（2時間）
**対応フェーズ**: v0.4

#### 提案内容

```json
// config/dev.json（追加）
{
  "wrappers": {
    "default_timeout": 30,
    "status_timeout": 10,
    "restart_timeout": 60,
    "logs_timeout": 15
  }
}
```

---

### IMP-008: ログローテーション設定の明確化

**カテゴリ**: ログ
**優先度**: LOW
**工数**: 小（4時間）
**対応フェーズ**: v0.4

#### 提案内容

```json
// config/prod.json（追加）
{
  "logging": {
    "level": "INFO",
    "file": "/var/log/adminui/app.log",
    "max_size": "50MB",
    "backup_count": 30,
    "rotation": "daily"
  },
  "audit_log": {
    "directory": "/var/log/adminui/audit",
    "retention_days": 90,
    "rotation": "daily",
    "compression": true
  }
}
```

---

## 📊 実装ロードマップ

### v0.2（現在フェーズ）

- [x] 要件定義・セキュリティレビュー
- [ ] Running Processes モジュール実装

### v0.3（本番準備）

**Week 1**:
- [ ] IMP-001: 本番環境認証実装（40時間）

**Week 2**:
- [ ] IMP-002: HTTPS強制実装（16時間）
- [ ] IMP-003: レート制限実装（12時間）

**Week 3**:
- [ ] IMP-004: テストカバレッジ向上（20時間）
- [ ] IMP-005: CI/CD依存関係スキャン（4時間）

**Week 4**:
- [ ] IMP-006: セキュリティ運用手順書（16時間）
- [ ] v0.3 総合テスト・リリース

### v0.4（機能拡張）

- [ ] IMP-007: タイムアウト設定ファイル化
- [ ] IMP-008: ログローテーション設定明確化
- [ ] 承認フロー実装
- [ ] 高度な監査機能

---

## 📝 まとめ

本改善提案リストは、**セキュリティファーストの原則**に基づき、
v0.3（本番準備）で対応すべき **CRITICAL / HIGH 優先度項目** を明確化しました。

**最優先対応項目**:
1. **IMP-001**: 本番環境認証（CRITICAL）
2. **IMP-002**: HTTPS強制（CRITICAL）
3. **IMP-003**: レート制限（HIGH）

これらを v0.3 で完了することで、**本番環境での安全な運用**が可能になります。

---

**作成者**: Security SubAgent（@Security / @Architect / @QA / @CIManager）
**承認者**: Team Lead
**次回レビュー**: v0.3 実装完了時

---

**📌 本提案リストは定期的に更新し、最新の脅威に対応すること。**

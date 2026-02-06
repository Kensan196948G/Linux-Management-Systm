# Running Processes モジュール - セキュリティ要件定義書

**作成日**: 2026-02-06
**バージョン**: 1.0
**対象モジュール**: Running Processes Management (Phase 2 v0.2)
**承認者**: [人間レビュアー署名欄]

---

## 📘 文書概要

| 項目 | 内容 |
|------|------|
| 文書名 | Running Processes モジュール セキュリティ要件定義書 |
| 目的 | プロセス管理機能のセキュリティ要件を明確化 |
| 対象読者 | @arch-reviewer, @code-implementer, @test-designer, @security-checker |
| 関連文書 | CLAUDE.md, SECURITY.md, THREAT_ANALYSIS_PROCESSES.md |

---

## 🎯 セキュリティ目標

### 機密性（Confidentiality）

- **[C1]** 他ユーザーのプロセス情報への不正アクセスを防止
- **[C2]** 機密情報（パスワード、トークン、APIキー）の露出を防止
- **[C3]** 環境変数の不適切な露出を防止

### 整合性（Integrity）

- **[I1]** コマンドインジェクション攻撃からシステムを保護
- **[I2]** 全操作の監査証跡を保全（改ざん防止）
- **[I3]** 入力バリデーションの厳格な実施

### 可用性（Availability）

- **[A1]** レート制限によるDoS攻撃の防止
- **[A2]** リソース枯渇攻撃の防止
- **[A3]** 正規ユーザーのサービス継続性確保

---

## 🔒 セキュリティ要件

### SR-1: 入力バリデーション（必須）

#### SR-1.1: PID 検証

**要件レベル**: 🔴 必須（MUST）

**要件**:
- PID は正の整数のみ許可（1 ~ 4,194,304）
- 範囲外の PID は即座に拒否
- 非整数の入力は Pydantic で自動拒否

**実装**:
```python
from pydantic import BaseModel, Field

class ProcessPIDRequest(BaseModel):
    pid: int = Field(
        ge=1,
        le=4194304,
        description="プロセスID（1 ~ 4,194,304）"
    )
```

**テスト**:
- 境界値テスト（0, 1, 4194304, 4194305）
- 負の値、浮動小数点、文字列の拒否

**根拠**: CWE-20（Improper Input Validation）対策

---

#### SR-1.2: フィルタ文字列検証

**要件レベル**: 🔴 必須（MUST）

**要件**:
- CLAUDE.md 定義の FORBIDDEN_CHARS を全て拒否
- 英数字、ハイフン、アンダースコア、ドットのみ許可
- 最大長 100 文字
- 空文字列は許可（フィルタなしを意味）

**禁止文字**:
```python
FORBIDDEN_CHARS = [
    ";", "|", "&", "$", "(", ")", "`",
    ">", "<", "*", "?", "{", "}", "[", "]",
    "\n", "\r"
]
```

**実装**:
```python
import re
from pydantic import BaseModel, Field, field_validator

class ProcessFilterRequest(BaseModel):
    filter: str = Field(
        max_length=100,
        description="プロセス名フィルタ（英数字、-_.のみ）"
    )

    @field_validator('filter')
    @classmethod
    def validate_filter(cls, v: str) -> str:
        # 空文字列は許可
        if not v:
            return v

        # 特殊文字チェック
        for char in FORBIDDEN_CHARS:
            if char in v:
                raise ValueError(f"Forbidden character detected: {char}")

        # 正規表現検証
        if not re.match(r'^[a-zA-Z0-9\-_.]+$', v):
            raise ValueError("Filter contains invalid characters")

        return v
```

**テスト**:
- 全 FORBIDDEN_CHARS の個別テスト（15+ ケース）
- コマンドインジェクションペイロードの拒否
- 安全な文字列の許可

**根拠**: OWASP A03:2021（Injection）対策

---

### SR-2: アクセス制御（RBAC）

#### SR-2.1: ロール別権限マトリクス

**要件レベル**: 🔴 必須（MUST）

| ロール | プロセス一覧 | プロセス詳細 | cmdline | environ | 他ユーザープロセス |
|--------|----------|----------|---------|---------|---------------|
| **Viewer** | ✅ 許可 | ✅ 許可 | ⚠️ マスク | ❌ 拒否 | ❌ 拒否 |
| **Operator** | ✅ 許可 | ✅ 許可 | ⚠️ マスク | ❌ 拒否 | ⚠️ 限定許可 |
| **Approver** | ✅ 許可 | ✅ 許可 | ⚠️ マスク | ⚠️ 限定許可 | ✅ 許可 |
| **Admin** | ✅ 許可 | ✅ 許可 | ✅ 許可 | ⚠️ 慎重に扱う | ✅ 許可 |

**注記**:
- ⚠️ マスク: パスワード関連キーワードを含む引数を `***REDACTED***` に置換
- ⚠️ 限定許可: 設計次第で制限
- ⚠️ 慎重に扱う: Admin でも環境変数は慎重に扱う（人間承認必須）

---

#### SR-2.2: 機密情報マスク処理

**要件レベル**: 🔴 必須（MUST）

**機密キーワード**:
```python
PASSWORD_KEYWORDS = [
    "password", "passwd", "pwd",
    "token", "key", "secret",
    "auth", "credential", "api_key"
]
```

**マスク対象**:
- コマンドライン引数（`cmdline`）
- 環境変数（`environ`）- ロールによっては全て非表示

**実装**:
```python
def mask_sensitive_cmdline(cmdline: list[str], user_role: str) -> list[str]:
    """コマンドライン引数のマスク処理

    Args:
        cmdline: コマンドライン引数のリスト
        user_role: ユーザーロール

    Returns:
        マスク済みコマンドライン引数
    """
    if user_role == "Admin":
        # Admin は全て表示（ただし警告付き）
        return cmdline

    masked = []
    for arg in cmdline:
        # パスワード関連キーワードを検出
        if any(kw in arg.lower() for kw in PASSWORD_KEYWORDS):
            masked.append("***REDACTED***")
        else:
            masked.append(arg)

    return masked


def filter_environ(environ: dict[str, str], user_role: str) -> dict[str, str] | None:
    """環境変数のフィルタリング

    Args:
        environ: 環境変数の辞書
        user_role: ユーザーロール

    Returns:
        フィルタ済み環境変数（Viewer/Operatorは None）
    """
    if user_role in ["Viewer", "Operator"]:
        # 環境変数は全て非表示
        return None

    if user_role == "Approver":
        # 機密環境変数のみマスク
        filtered = {}
        for key, value in environ.items():
            if any(kw in key.lower() for kw in PASSWORD_KEYWORDS):
                filtered[key] = "***REDACTED***"
            else:
                filtered[key] = value
        return filtered

    # Admin
    # 人間承認が必要（設計時に確認）
    return environ
```

**テスト**:
- 各ロールのマスク処理テスト
- パスワードキーワードの検出精度テスト

**根拠**: OWASP A02:2021（Cryptographic Failures）、CWE-200（Exposure of Sensitive Information）対策

---

### SR-3: レート制限

#### SR-3.1: API レート制限

**要件レベル**: 🟡 高優先度（SHOULD）

**レート制限設定**:

| エンドポイント | ユーザー単位 | IP単位 | バースト |
|--------------|----------|--------|---------|
| `GET /api/processes` | 60 req/min | 100 req/min | 10 |
| `GET /api/processes/{pid}` | 120 req/min | 200 req/min | 20 |

**実装**:
```python
from slowapi import Limiter
from slowapi.util import get_remote_address

limiter = Limiter(key_func=get_remote_address)

@router.get("/processes")
@limiter.limit("60/minute")
async def list_processes(
    request: Request,
    current_user: User = Depends(get_current_user)
):
    ...

@router.get("/processes/{pid}")
@limiter.limit("120/minute")
async def get_process_detail(
    request: Request,
    pid: int,
    current_user: User = Depends(get_current_user)
):
    ...
```

**エラーレスポンス**:
```json
{
  "status": "error",
  "code": 429,
  "message": "Rate limit exceeded. Please try again later.",
  "retry_after": 30
}
```

**テスト**:
- 閾値超過時の 429 エラー
- ユーザー別の独立性
- リセット後の再アクセス

**根拠**: OWASP A04:2021（Insecure Design）、DoS攻撃対策

---

### SR-4: 監査ログ

#### SR-4.1: 監査ログ記録要件

**要件レベル**: 🔴 必須（MUST）

**記録対象**:
- 全てのプロセス情報取得操作
- 成功・失敗にかかわらず記録
- 入力検証エラーも記録

**必須フィールド**:
```python
audit_entry = {
    "timestamp": "2026-02-06T12:34:56.789Z",      # ISO 8601形式
    "user_id": "operator@example.com",             # ユーザーID
    "user_role": "Operator",                       # ロール
    "operation": "process_list | process_detail",  # 操作種別
    "target": "all | pid:1234",                    # 対象
    "filter": "nginx",                             # フィルタ（該当時）
    "result_count": 42,                            # 返却件数
    "status": "success | failure",                 # 結果
    "client_ip": "192.168.1.100",                  # クライアントIP
    "response_time_ms": 123,                       # 応答時間
    "error": "error message if failed"             # エラー詳細（失敗時）
}
```

**実装**:
```python
from backend.core.audit_log import audit_log

try:
    # プロセス情報取得
    processes = await get_processes(filter_str)

    # 成功ログ
    audit_log.record(
        operation="process_list",
        user_id=current_user.email,
        target="all",
        status="success",
        details={
            "filter": filter_str,
            "result_count": len(processes),
            "client_ip": request.client.host,
            "response_time_ms": response_time
        }
    )

except Exception as e:
    # 失敗ログ
    audit_log.record(
        operation="process_list",
        user_id=current_user.email,
        target="all",
        status="failure",
        details={
            "filter": filter_str,
            "error": str(e),
            "client_ip": request.client.host
        }
    )
    raise
```

**保管要件**:
- 追記専用（改ざん防止）
- 日別ファイル（`audit_YYYYMMDD.json`）
- 最低 90 日間保管
- 定期バックアップ（推奨）

**テスト**:
- 成功操作のログ記録
- 失敗操作のログ記録
- フィールドの完全性

**根拠**: CLAUDE.md Section 5（監査証跡）、コンプライアンス要件

---

### SR-5: sudo ラッパースクリプト

#### SR-5.1: ラッパー設計原則

**要件レベル**: 🔴 必須（MUST）

**ファイルパス**: `/usr/local/sbin/adminui-processes.sh`

**必須設定**:
```bash
#!/bin/bash
set -euo pipefail  # 必須
```

**引数検証**:
- PID: 数字のみ、範囲チェック（1 ~ 4194304）
- フィルタ: 特殊文字チェック、正規表現検証

**特殊文字検証**:
```bash
if [[ "$FILTER" =~ [';|&$(){}[\]`<>*?] ]]; then
    error "Invalid filter: forbidden characters detected"
    exit 1
fi
```

**コマンド実行**:
- 配列渡しのみ（shell展開禁止）
- `bash -c` 禁止
- `eval` 禁止

**ログ記録**:
```bash
log() {
    logger -t adminui-processes -p user.info "$*"
    echo "[$(date -Iseconds)] $*" >&2
}

error() {
    logger -t adminui-processes -p user.err "ERROR: $*"
    echo "[$(date -Iseconds)] ERROR: $*" >&2
}
```

**実装例**:
```bash
#!/bin/bash
set -euo pipefail

log "Process operation started by UID=$UID"

COMMAND="$1"
shift

case "$COMMAND" in
    list)
        FILTER="${1:-}"

        # フィルタ検証
        if [[ "$FILTER" =~ [';|&$(){}[\]`<>*?] ]]; then
            error "Invalid filter: forbidden characters"
            exit 1
        fi

        # プロセス一覧取得
        if [ -z "$FILTER" ]; then
            ps aux --no-headers
        else
            ps aux --no-headers | grep -F "$FILTER"
        fi
        ;;

    detail)
        PID="$1"

        # PID 検証
        if ! [[ "$PID" =~ ^[0-9]+$ ]]; then
            error "Invalid PID: must be numeric"
            exit 1
        fi

        if [ "$PID" -lt 1 ] || [ "$PID" -gt 4194304 ]; then
            error "Invalid PID: out of range"
            exit 1
        fi

        # プロセス詳細取得
        cat "/proc/$PID/cmdline" 2>/dev/null || error "Process not found"
        ;;

    *)
        error "Unknown command: $COMMAND"
        exit 1
        ;;
esac

log "Process operation completed successfully"
exit 0
```

**テスト**:
- 正常系（フィルタあり/なし）
- 異常系（特殊文字、無効なPID）
- ShellCheck 検証

**根拠**: CLAUDE.md Section 3（Shell禁止、sudo最小化）

---

#### SR-5.2: 実行権限 ✅ **sudo不使用（承認済み）**

**要件レベル**: 🔴 必須（MUST）

**決定事項**:
- **sudo不使用**: `ps aux` は一般ユーザー権限で実行可能
- **実行ユーザー**: `svc-adminui`（一般ユーザー）
- **sudoers 追加不要**: セキュリティリスク最小化

**実装**:
```python
# backend/core/sudo_wrapper.py（修正版）
def get_processes(filter_str: str = "") -> dict[str, Any]:
    """プロセス一覧を取得（sudo不使用）"""
    wrapper_path = self.wrapper_dir / "adminui-processes.sh"

    # sudo なしで実行
    cmd = [str(wrapper_path), "list"]
    if filter_str:
        cmd.append(filter_str)

    result = subprocess.run(
        cmd,  # sudo 不使用
        check=True,
        capture_output=True,
        text=True,
        timeout=30
    )
    return json.loads(result.stdout)
```

**ファイル配置**:
```
# ラッパースクリプトの配置
/usr/local/bin/adminui-processes.sh  # 一般ユーザー実行可能
chmod 755 /usr/local/bin/adminui-processes.sh
```

**根拠**: CLAUDE.md Section 4（Least Privilege）、AP-1 承認決定

---

### SR-6: エラーハンドリング

#### SR-6.1: セキュリティエラーの処理

**要件レベル**: 🔴 必須（MUST）

**エラー種別**:

| エラー | HTTPステータス | ログレベル | ユーザー通知 |
|--------|--------------|----------|-----------|
| 入力検証エラー | 422 | INFO | 詳細表示 |
| 権限不足 | 403 | WARNING | 一般メッセージ |
| レート制限超過 | 429 | WARNING | リトライ時刻 |
| プロセス未発見 | 404 | INFO | 詳細表示 |
| 内部エラー | 500 | ERROR | 一般メッセージ |

**セキュリティ原則**:
- **情報漏洩防止**: 内部エラーの詳細はユーザーに返さない
- **監査ログ**: 全エラーを記録
- **一般化**: 権限エラーは「Access Denied」のみ

**実装**:
```python
@router.get("/processes/{pid}")
async def get_process_detail(
    pid: int,
    current_user: User = Depends(get_current_user)
):
    try:
        # プロセス取得
        process = await sudo_wrapper.get_process(pid)

        # RBAC チェック
        if not has_permission(current_user.role, process.user):
            audit_log.record(
                operation="process_detail",
                user_id=current_user.email,
                target=f"pid:{pid}",
                status="failure",
                details={"error": "Permission denied"}
            )
            raise HTTPException(
                status_code=403,
                detail="Access denied"  # 詳細は返さない
            )

        # 機密情報マスク
        process = mask_sensitive_data(process, current_user.role)

        audit_log.record(
            operation="process_detail",
            user_id=current_user.email,
            target=f"pid:{pid}",
            status="success"
        )

        return process

    except ValueError as e:
        # 入力検証エラー
        audit_log.record(
            operation="process_detail",
            user_id=current_user.email,
            target=f"pid:{pid}",
            status="failure",
            details={"error": str(e)}
        )
        raise HTTPException(status_code=422, detail=str(e))

    except PermissionError as e:
        # 権限エラー
        audit_log.record(
            operation="process_detail",
            user_id=current_user.email,
            target=f"pid:{pid}",
            status="failure",
            details={"error": "Permission denied"}
        )
        raise HTTPException(status_code=403, detail="Access denied")

    except Exception as e:
        # 内部エラー
        logger.error(f"Internal error: {e}", exc_info=True)
        audit_log.record(
            operation="process_detail",
            user_id=current_user.email,
            target=f"pid:{pid}",
            status="failure",
            details={"error": "Internal error"}
        )
        raise HTTPException(
            status_code=500,
            detail="Internal server error"  # 詳細は返さない
        )
```

**根拠**: OWASP A05:2021（Security Misconfiguration）、CWE-209（Information Exposure Through an Error Message）対策

---

## 🧪 テスト要件

### TR-1: セキュリティテストカバレッジ

**要件レベル**: 🔴 必須（MUST）

**最小テストケース数**:
- コマンドインジェクション: 15+ ケース
- PID バリデーション: 8+ ケース
- RBAC: 8+ ケース
- レート制限: 4+ ケース
- 監査ログ: 4+ ケース
- 機密情報保護: 6+ ケース
- セキュリティ原則検証: 6+ ケース

**合計**: 50+ テストケース

**カバレッジ目標**:
- `backend/api/routes/processes.py`: **90%以上**
- `wrappers/adminui-processes.sh`: **全パターン**

---

### TR-2: 静的解析

**要件レベル**: 🔴 必須（MUST）

**ツール**:
- **Bandit**: Python セキュリティスキャン
- **ShellCheck**: Bash スクリプト検証
- **Grep**: 禁止パターン検出

**禁止パターン（検出 → 即失敗）**:
```bash
# Python
grep -r "shell=True" backend/
grep -rE "os\.system\s*\(" backend/
grep -rE "\b(eval|exec)\s*\(" backend/

# Bash
grep -r "bash -c" wrappers/
```

**合格基準**:
- Bandit: High/Medium の問題ゼロ
- ShellCheck: エラーゼロ
- Grep: 禁止パターンゼロ検出

---

## 📋 人間承認決定事項（APPROVED）

以下の項目について**人間による承認完了**（承認日: 2026-02-06）

### AP-1: sudoers 変更 ✅ **承認済み**
- **決定**: **sudo不使用** - `ps aux` は一般ユーザー権限で実行可能
- **理由**: `ps` コマンドは root 権限不要、セキュリティリスク低減
- **実装**: ラッパースクリプトを一般ユーザーで実行（sudoers 追加不要）

### AP-2: 機密情報の扱い ✅ **承認済み**
- **決定**: **マスク必須**
  - Viewer/Operator: `cmdline` マスク、`environ` 非表示
  - Admin: 全表示（警告付き）
- **マスクルール**: PASSWORD_KEYWORDS 検出時に `***REDACTED***` に置換
- **実装**: `mask_sensitive_cmdline()`, `filter_environ()` 関数

### AP-3: レート制限 ✅ **承認済み**
- **決定**: **60 req/min 承認**
  - プロセス一覧: 60 req/min/user
  - プロセス詳細: 120 req/min/user
- **開発環境**: レート制限無効化可能（環境変数で制御）
- **実装**: slowapi を使用、`@limiter.limit("60/minute")`

### AP-4: RBAC ✅ **承認済み**
- **決定**: **Viewer 全プロセス閲覧可**（ただし機密情報マスク）
- **理由**: 運用監視のため全プロセスの状態確認が必要
- **制約**: `cmdline` マスク、`environ` 非表示で機密情報保護
- **Operator**: Viewer と同等（将来的に操作権限追加可能性）

---

## 📊 コンプライアンスマッピング

### OWASP Top 10 (2021)

| OWASP カテゴリ | 該当要件 | 対策状況 |
|--------------|---------|---------|
| A01:2021 – Broken Access Control | SR-2 (RBAC) | ✅ 対策済み |
| A02:2021 – Cryptographic Failures | SR-2.2 (機密情報マスク) | ✅ 対策済み |
| A03:2021 – Injection | SR-1 (入力バリデーション) | ✅ 対策済み |
| A04:2021 – Insecure Design | SR-3 (レート制限) | ✅ 対策済み |
| A05:2021 – Security Misconfiguration | SR-6 (エラーハンドリング) | ✅ 対策済み |

### CWE Top 25

| CWE | 名称 | 該当要件 |
|-----|------|---------|
| CWE-20 | Improper Input Validation | SR-1 |
| CWE-78 | OS Command Injection | SR-1, SR-5 |
| CWE-200 | Exposure of Sensitive Information | SR-2.2, SR-6 |
| CWE-209 | Information Exposure Through Error | SR-6 |
| CWE-732 | Incorrect Permission Assignment | SR-2 |

---

## ✅ 承認欄

### セキュリティ要件承認

- [x] **@arch-reviewer**: セキュリティアーキテクチャ承認
- [x] **@security-checker**: セキュリティ要件レビュー完了
- [x] **team-lead（人間レビュアー）**: 最終承認

**承認日**: 2026-02-06
**承認者**: team-lead
**承認内容**: AP-1～AP-4 全決定事項承認、実装フェーズ開始許可

---

## 📚 参照文書

- [CLAUDE.md](../../CLAUDE.md) - セキュリティ開発ガイドライン
- [SECURITY.md](../../SECURITY.md) - セキュリティポリシー
- [THREAT_ANALYSIS_PROCESSES.md](./THREAT_ANALYSIS_PROCESSES.md) - 脅威分析
- [SECURITY_CHECKLIST_PROCESSES.md](./SECURITY_CHECKLIST_PROCESSES.md) - セキュリティチェックリスト
- [OWASP Top 10 2021](https://owasp.org/www-project-top-ten/)

---

**最終更新**: 2026-02-06
**次回レビュー**: 実装完了後、または仕様変更時

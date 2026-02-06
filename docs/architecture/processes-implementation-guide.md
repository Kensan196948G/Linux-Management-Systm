# Running Processes モジュール 実装ガイド

**作成日**: 2026-02-06
**対象**: backend-impl, frontend-impl
**関連**: [processes-module-design.md](./processes-module-design.md)

---

## 📋 実装タスク一覧

### Backend実装（backend-impl）

| タスクID | タスク名 | ファイル | 優先度 | 推定時間 |
|---------|---------|---------|-------|---------|
| BE-1 | sudo_wrapper.py メソッド追加 | `backend/core/sudo_wrapper.py` | 🔴 HIGH | 30分 |
| BE-2 | Wrapper スクリプト作成 | `wrappers/adminui-processes.sh` | 🔴 HIGH | 2時間 |
| BE-3 | API Route 作成 | `backend/api/routes/processes.py` | 🔴 HIGH | 2時間 |
| BE-4 | API ルーター登録 | `backend/api/routes/__init__.py` | 🟡 MEDIUM | 10分 |
| BE-5 | ユニットテスト作成 | `tests/test_processes.py` | 🔴 HIGH | 1時間 |
| BE-6 | Wrapper テスト作成 | `wrappers/test/test-adminui-processes.sh` | 🟡 MEDIUM | 1時間 |

**合計推定時間**: 6.5時間

### Frontend実装（frontend-impl）

| タスクID | タスク名 | ファイル | 優先度 | 推定時間 |
|---------|---------|---------|-------|---------|
| FE-1 | HTML テンプレート作成 | `frontend/processes.html` | 🔴 HIGH | 1時間 |
| FE-2 | JavaScript 実装 | `frontend/js/processes.js` | 🔴 HIGH | 2時間 |
| FE-3 | CSS スタイリング | `frontend/css/style.css` | 🟡 MEDIUM | 30分 |
| FE-4 | ナビゲーション追加 | `frontend/index.html` | 🟢 LOW | 15分 |
| FE-5 | ブラウザテスト | - | 🟡 MEDIUM | 30分 |

**合計推定時間**: 4時間

---

## 🔧 Backend実装詳細

### BE-1: sudo_wrapper.py メソッド追加

**ファイル**: `backend/core/sudo_wrapper.py`

**追加コード**:

```python
from typing import Optional

def get_processes(
    self,
    sort_by: str = "cpu",
    limit: int = 100,
    filter_user: Optional[str] = None,
    min_cpu: float = 0.0,
    min_mem: float = 0.0,
) -> Dict[str, Any]:
    """
    プロセス一覧を取得

    Args:
        sort_by: ソートキー (cpu/mem/pid/time)
        limit: 取得件数 (1-1000)
        filter_user: ユーザー名フィルタ (allowlist検証済み)
        min_cpu: 最小CPU使用率 (0.0-100.0)
        min_mem: 最小メモリ使用率 (0.0-100.0)

    Returns:
        プロセス情報の辞書

    Raises:
        SudoWrapperError: 実行失敗時
    """
    args = [
        f"--sort={sort_by}",
        f"--limit={limit}",
    ]

    if filter_user:
        args.append(f"--filter-user={filter_user}")
    if min_cpu > 0.0:
        args.append(f"--min-cpu={min_cpu}")
    if min_mem > 0.0:
        args.append(f"--min-mem={min_mem}")

    return self._execute("adminui-processes.sh", args, timeout=10)
```

**チェックポイント**:
- [ ] 型ヒントが完全に記載されている
- [ ] docstring が記載されている
- [ ] タイムアウトが設定されている（10秒）

---

### BE-2: Wrapper スクリプト作成

**ファイル**: `wrappers/adminui-processes.sh`

**実装ポイント**:

1. **shebang と set -euo pipefail**

```bash
#!/bin/bash
set -euo pipefail
```

2. **allowlist 定義**

```bash
# 許可ユーザーリスト
ALLOWED_USERS=(
    "root"
    "www-data"
    "postgres"
    "redis"
    "nginx"
    "adminui"
)

# 許可ソートキー
ALLOWED_SORTS=(
    "cpu"
    "mem"
    "pid"
    "time"
)

# 禁止文字
FORBIDDEN_CHARS='[;|&$()` ><*?{}[\]]'
```

3. **引数パース**

```bash
# デフォルト値
SORT_BY="cpu"
LIMIT=100
FILTER_USER=""
MIN_CPU=0.0
MIN_MEM=0.0

# 引数パース
while [[ $# -gt 0 ]]; do
    case "$1" in
        --sort=*)
            SORT_BY="${1#*=}"
            shift
            ;;
        --limit=*)
            LIMIT="${1#*=}"
            shift
            ;;
        --filter-user=*)
            FILTER_USER="${1#*=}"
            shift
            ;;
        --min-cpu=*)
            MIN_CPU="${1#*=}"
            shift
            ;;
        --min-mem=*)
            MIN_MEM="${1#*=}"
            shift
            ;;
        *)
            error "Unknown argument: $1"
            exit 1
            ;;
    esac
done
```

4. **入力検証**

```bash
# ソートキーの検証
validate_sort_key "$SORT_BY"

# ユーザー名の検証
if [ -n "$FILTER_USER" ]; then
    validate_user "$FILTER_USER"
fi

# 数値範囲の検証
if [ "$LIMIT" -lt 1 ] || [ "$LIMIT" -gt 1000 ]; then
    error "Limit out of range: $LIMIT"
    exit 1
fi
```

5. **ps コマンド実行**

```bash
# ps コマンド構築
PS_ARGS=("aux")

# ソートオプション
case "$SORT_BY" in
    cpu)
        PS_ARGS+=("--sort=-%cpu")
        ;;
    mem)
        PS_ARGS+=("--sort=-%mem")
        ;;
    pid)
        PS_ARGS+=("--sort=pid")
        ;;
    time)
        PS_ARGS+=("--sort=-time")
        ;;
esac

# ユーザーフィルタ
if [ -n "$FILTER_USER" ]; then
    PS_ARGS+=("--user" "$FILTER_USER")
fi

# 実行
OUTPUT=$(ps "${PS_ARGS[@]}" 2>&1)
```

6. **JSON 出力**

```bash
# JSON 構築
echo "{"
echo "  \"status\": \"success\","
echo "  \"total_processes\": $TOTAL,"
echo "  \"returned_processes\": $RETURNED,"
echo "  \"sort_by\": \"$SORT_BY\","
echo "  \"filters\": {"
echo "    \"user\": \"$FILTER_USER\","
echo "    \"min_cpu\": $MIN_CPU,"
echo "    \"min_mem\": $MIN_MEM"
echo "  },"
echo "  \"processes\": ["

# プロセス情報を JSON 配列として出力
FIRST=true
while IFS= read -r line; do
    # ヘッダー行をスキップ
    if [[ "$line" =~ ^USER ]]; then
        continue
    fi

    # パース
    USER=$(echo "$line" | awk '{print $1}')
    PID=$(echo "$line" | awk '{print $2}')
    CPU=$(echo "$line" | awk '{print $3}')
    MEM=$(echo "$line" | awk '{print $4}')
    VSZ=$(echo "$line" | awk '{print $5}')
    RSS=$(echo "$line" | awk '{print $6}')
    TTY=$(echo "$line" | awk '{print $7}')
    STAT=$(echo "$line" | awk '{print $8}')
    START=$(echo "$line" | awk '{print $9}')
    TIME=$(echo "$line" | awk '{print $10}')
    COMMAND=$(echo "$line" | awk '{for(i=11;i<=NF;i++) printf "%s ", $i}')

    # フィルタ適用
    if (( $(echo "$CPU < $MIN_CPU" | bc -l) )); then
        continue
    fi
    if (( $(echo "$MEM < $MIN_MEM" | bc -l) )); then
        continue
    fi

    # JSON 出力
    if [ "$FIRST" = false ]; then
        echo ","
    fi
    FIRST=false

    echo -n "    {\"pid\": $PID, \"user\": \"$USER\", \"cpu_percent\": $CPU, \"mem_percent\": $MEM, \"vsz\": $VSZ, \"rss\": $RSS, \"tty\": \"$TTY\", \"stat\": \"$STAT\", \"start\": \"$START\", \"time\": \"$TIME\", \"command\": \"$COMMAND\"}"

    # limit 到達チェック
    COUNT=$((COUNT + 1))
    if [ "$COUNT" -ge "$LIMIT" ]; then
        break
    fi
done <<< "$OUTPUT"

echo ""
echo "  ],"
echo "  \"timestamp\": \"$(date -Iseconds)\""
echo "}"
```

**チェックポイント**:
- [ ] `set -euo pipefail` が設定されている
- [ ] allowlist が定義されている
- [ ] 特殊文字検証が実装されている
- [ ] 配列渡しでコマンド実行している
- [ ] logger でログ出力している
- [ ] JSON 形式で出力している

---

### BE-3: API Route 作成

**ファイル**: `backend/api/routes/processes.py`

**実装テンプレート**:

```python
"""
プロセス管理 API エンドポイント
"""

import logging
from typing import Optional

from fastapi import APIRouter, Depends, HTTPException, Query, status
from pydantic import BaseModel, Field

from ...core import get_current_user, require_permission, sudo_wrapper
from ...core.audit_log import audit_log
from ...core.auth import TokenData
from ...core.sudo_wrapper import SudoWrapperError

logger = logging.getLogger(__name__)

router = APIRouter(prefix="/processes", tags=["processes"])


# ===================================================================
# レスポンスモデル
# ===================================================================


class ProcessInfo(BaseModel):
    """プロセス情報"""

    pid: int
    user: str
    cpu_percent: float
    mem_percent: float
    vsz: int
    rss: int
    tty: str
    stat: str
    start: str
    time: str
    command: str


class ProcessListResponse(BaseModel):
    """プロセス一覧レスポンス"""

    status: str
    total_processes: int
    returned_processes: int
    sort_by: str
    filters: dict
    processes: list[ProcessInfo]
    timestamp: str


# ===================================================================
# エンドポイント
# ===================================================================


@router.get("", response_model=ProcessListResponse)
async def list_processes(
    sort_by: str = Query("cpu", regex="^(cpu|mem|pid|time)$"),
    limit: int = Query(100, ge=1, le=1000),
    filter_user: Optional[str] = Query(None, min_length=1, max_length=32, regex="^[a-zA-Z0-9_-]+$"),
    min_cpu: float = Query(0.0, ge=0.0, le=100.0),
    min_mem: float = Query(0.0, ge=0.0, le=100.0),
    current_user: TokenData = Depends(require_permission("read:processes")),
):
    """
    プロセス一覧を取得

    Args:
        sort_by: ソートキー (cpu/mem/pid/time)
        limit: 取得件数 (1-1000)
        filter_user: ユーザー名フィルタ
        min_cpu: 最小CPU使用率 (0.0-100.0)
        min_mem: 最小メモリ使用率 (0.0-100.0)
        current_user: 現在のユーザー (read:processes 権限必須)

    Returns:
        プロセス一覧

    Raises:
        HTTPException: 取得失敗時
    """
    logger.info(
        f"Process list requested: sort={sort_by}, limit={limit}, "
        f"user={filter_user}, min_cpu={min_cpu}, min_mem={min_mem}, "
        f"by={current_user.username}"
    )

    # 監査ログ記録（試行）
    audit_log.record(
        operation="process_list",
        user_id=current_user.user_id,
        target="system",
        status="attempt",
        details={
            "sort_by": sort_by,
            "limit": limit,
            "filter_user": filter_user,
            "min_cpu": min_cpu,
            "min_mem": min_mem,
        },
    )

    try:
        # sudo ラッパー経由でプロセス一覧を取得
        result = sudo_wrapper.get_processes(
            sort_by=sort_by,
            limit=limit,
            filter_user=filter_user,
            min_cpu=min_cpu,
            min_mem=min_mem,
        )

        # ラッパーがエラーを返した場合
        if result.get("status") == "error":
            # 監査ログ記録（拒否）
            audit_log.record(
                operation="process_list",
                user_id=current_user.user_id,
                target="system",
                status="denied",
                details={"reason": result.get("message", "unknown")},
            )

            raise HTTPException(
                status_code=status.HTTP_403_FORBIDDEN,
                detail=result.get("message", "Process list denied"),
            )

        # 監査ログ記録（成功）
        audit_log.record(
            operation="process_list",
            user_id=current_user.user_id,
            target="system",
            status="success",
            details={"returned_processes": result.get("returned_processes", 0)},
        )

        logger.info(f"Process list retrieved: {result.get('returned_processes', 0)} processes")

        return ProcessListResponse(**result)

    except SudoWrapperError as e:
        # 監査ログ記録（失敗）
        audit_log.record(
            operation="process_list",
            user_id=current_user.user_id,
            target="system",
            status="failure",
            details={"error": str(e)},
        )

        logger.error(f"Process list failed: error={e}")

        raise HTTPException(
            status_code=status.HTTP_500_INTERNAL_SERVER_ERROR,
            detail=f"Process list retrieval failed: {str(e)}",
        )
```

**チェックポイント**:
- [ ] Pydantic モデルが定義されている
- [ ] 型ヒント・docstring が完全
- [ ] Pydantic で入力検証している（regex, ge, le）
- [ ] 認可チェック（`require_permission("read:processes")`）
- [ ] 監査ログが記録されている（attempt, success, denied, failure）
- [ ] エラーハンドリングが実装されている

---

### BE-4: API ルーター登録

**ファイル**: `backend/api/routes/__init__.py`

**追加コード**:

```python
from .processes import router as processes_router

# ルーター登録（既存のコードに追加）
app.include_router(processes_router, prefix="/api/v1")
```

---

### BE-5: ユニットテスト作成

**ファイル**: `tests/test_processes.py`

**テストケース**:

```python
"""
プロセス管理 API のテスト
"""

import pytest
from fastapi.testclient import TestClient

# ===================================================================
# 正常系テスト
# ===================================================================


def test_list_processes_success(client: TestClient, admin_token: str):
    """プロセス一覧取得の正常系"""
    response = client.get(
        "/api/v1/processes",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "success"
    assert data["sort_by"] == "cpu"
    assert "processes" in data
    assert isinstance(data["processes"], list)


def test_list_processes_with_filters(client: TestClient, admin_token: str):
    """フィルタ付きプロセス一覧取得"""
    response = client.get(
        "/api/v1/processes?sort_by=mem&limit=50&filter_user=root&min_cpu=10.0",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert response.status_code == 200
    data = response.json()

    assert data["status"] == "success"
    assert data["sort_by"] == "mem"
    assert data["filters"]["user"] == "root"
    assert data["filters"]["min_cpu"] == 10.0


# ===================================================================
# 異常系テスト
# ===================================================================


def test_list_processes_invalid_sort(client: TestClient, admin_token: str):
    """不正なソートキー"""
    response = client.get(
        "/api/v1/processes?sort_by=invalid",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert response.status_code == 422  # Validation Error


def test_list_processes_invalid_limit(client: TestClient, admin_token: str):
    """範囲外の limit"""
    response = client.get(
        "/api/v1/processes?limit=9999",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert response.status_code == 422


def test_list_processes_invalid_user(client: TestClient, admin_token: str):
    """不正なユーザー名（特殊文字）"""
    response = client.get(
        "/api/v1/processes?filter_user=root; rm -rf /",
        headers={"Authorization": f"Bearer {admin_token}"},
    )

    assert response.status_code == 422


# ===================================================================
# 認証・認可テスト
# ===================================================================


def test_list_processes_no_auth(client: TestClient):
    """認証なし"""
    response = client.get("/api/v1/processes")
    assert response.status_code == 401


def test_list_processes_no_permission(client: TestClient, viewer_token: str):
    """権限なし"""
    response = client.get(
        "/api/v1/processes",
        headers={"Authorization": f"Bearer {viewer_token}"},
    )

    assert response.status_code == 403
```

**チェックポイント**:
- [ ] 正常系テスト（デフォルト、フィルタ付き）
- [ ] 異常系テスト（不正入力、範囲外、特殊文字）
- [ ] 認証・認可テスト
- [ ] カバレッジ 85% 以上

---

### BE-6: Wrapper テスト作成

**ファイル**: `wrappers/test/test-adminui-processes.sh`

**テストスクリプト**:

```bash
#!/bin/bash
set -euo pipefail

WRAPPER="../adminui-processes.sh"
PASS_COUNT=0
FAIL_COUNT=0

# テストヘルパー
pass() {
    echo "✅ PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "❌ FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

# ===================================================================
# 正常系テスト
# ===================================================================

# デフォルトパラメータ
if OUTPUT=$($WRAPPER 2>&1); then
    if echo "$OUTPUT" | jq -e '.status == "success"' > /dev/null; then
        pass "Default parameters"
    else
        fail "Default parameters: status not success"
    fi
else
    fail "Default parameters: execution failed"
fi

# ソート指定
if OUTPUT=$($WRAPPER --sort=mem --limit=10 2>&1); then
    if echo "$OUTPUT" | jq -e '.sort_by == "mem"' > /dev/null; then
        pass "Sort by mem"
    else
        fail "Sort by mem: incorrect sort_by"
    fi
else
    fail "Sort by mem: execution failed"
fi

# ユーザーフィルタ
if OUTPUT=$($WRAPPER --filter-user=root 2>&1); then
    if echo "$OUTPUT" | jq -e '.filters.user == "root"' > /dev/null; then
        pass "Filter by root user"
    else
        fail "Filter by root user: incorrect filter"
    fi
else
    fail "Filter by root user: execution failed"
fi

# ===================================================================
# 異常系テスト
# ===================================================================

# 不正なソートキー
if $WRAPPER --sort=invalid 2>&1 | grep -q "Invalid sort key"; then
    pass "Reject invalid sort key"
else
    fail "Should reject invalid sort key"
fi

# allowlist 外のユーザー
if $WRAPPER --filter-user=hacker 2>&1 | grep -q "not in allowlist"; then
    pass "Reject user not in allowlist"
else
    fail "Should reject user not in allowlist"
fi

# 特殊文字を含むユーザー
if $WRAPPER --filter-user="root; ls" 2>&1 | grep -q "Forbidden character"; then
    pass "Reject forbidden characters"
else
    fail "Should reject forbidden characters"
fi

# 範囲外の limit
if $WRAPPER --limit=9999 2>&1 | grep -q "out of range"; then
    pass "Reject out-of-range limit"
else
    fail "Should reject out-of-range limit"
fi

# ===================================================================
# 結果表示
# ===================================================================

echo ""
echo "=========================================="
echo "Test Results:"
echo "  PASS: $PASS_COUNT"
echo "  FAIL: $FAIL_COUNT"
echo "=========================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed."
    exit 1
fi
```

**チェックポイント**:
- [ ] 正常系テスト（デフォルト、ソート、フィルタ）
- [ ] 異常系テスト（不正入力、allowlist拒否、特殊文字）
- [ ] 全テストが自動実行可能

---

## 🎨 Frontend実装詳細

### FE-1: HTML テンプレート作成

**ファイル**: `frontend/processes.html`

設計ドキュメントの「コンポーネント設計 > 4. Frontend」の HTML をそのまま実装。

**チェックポイント**:
- [ ] フィルタリング UI（Sort by, User, Min CPU/MEM）
- [ ] プロセステーブル（11カラム）
- [ ] ボタン（Refresh, Auto-refresh）
- [ ] ステータス表示エリア

---

### FE-2: JavaScript 実装

**ファイル**: `frontend/js/processes.js`

設計ドキュメントの「コンポーネント設計 > 4. Frontend」の JavaScript をそのまま実装。

**チェックポイント**:
- [ ] ProcessManager クラス
- [ ] loadProcesses() メソッド
- [ ] renderProcessTable() メソッド
- [ ] toggleAutoRefresh() メソッド（5秒間隔）
- [ ] エラーハンドリング
- [ ] HTML エスケープ

---

### FE-3: CSS スタイリング

**ファイル**: `frontend/css/style.css`

```css
/* プロセステーブル */
#processTable {
    width: 100%;
    border-collapse: collapse;
    font-family: 'Courier New', monospace;
    font-size: 14px;
}

#processTable th {
    background-color: #2c3e50;
    color: white;
    padding: 12px 8px;
    text-align: left;
    font-weight: bold;
    border-bottom: 2px solid #34495e;
}

#processTable td {
    padding: 8px;
    border-bottom: 1px solid #ecf0f1;
}

#processTable tr:hover {
    background-color: #f8f9fa;
}

/* 高CPU使用率のハイライト */
#processTable tr.high-cpu {
    background-color: #fff3cd;
    font-weight: bold;
}

/* CPU/MEM カラム */
.cpu-usage, .mem-usage {
    font-weight: bold;
    text-align: right;
}

/* コマンド列 */
#processTable td.command {
    max-width: 350px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
    font-family: 'Courier New', monospace;
    font-size: 12px;
    color: #555;
}

/* フィルタコントロール */
.controls {
    display: flex;
    gap: 15px;
    margin-bottom: 20px;
    padding: 15px;
    background-color: #f8f9fa;
    border-radius: 5px;
    align-items: center;
}

.control-group {
    display: flex;
    flex-direction: column;
    gap: 5px;
}

.control-group label {
    font-size: 12px;
    font-weight: bold;
    color: #555;
}

.control-group select,
.control-group input {
    padding: 6px 10px;
    border: 1px solid #ced4da;
    border-radius: 4px;
    font-size: 14px;
}

/* ボタン */
#refreshBtn, #autoRefreshBtn {
    padding: 8px 15px;
    background-color: #007bff;
    color: white;
    border: none;
    border-radius: 4px;
    cursor: pointer;
    font-size: 14px;
    margin-left: auto;
}

#refreshBtn:hover, #autoRefreshBtn:hover {
    background-color: #0056b3;
}

/* ステータス表示 */
.status {
    margin-top: 10px;
    padding: 10px;
    border-radius: 4px;
    font-size: 14px;
}

.status.success {
    background-color: #d4edda;
    color: #155724;
}

.status.error {
    background-color: #f8d7da;
    color: #721c24;
}

.status.info {
    background-color: #d1ecf1;
    color: #0c5460;
}

/* Loading / No data */
.loading, .no-data {
    text-align: center;
    color: #6c757d;
    font-style: italic;
}
```

**チェックポイント**:
- [ ] テーブルスタイル
- [ ] 高CPU使用率のハイライト
- [ ] コマンド列の幅制限
- [ ] フィルタコントロールのレイアウト

---

### FE-4: ナビゲーション追加

**ファイル**: `frontend/index.html`

```html
<nav>
    <ul>
        <li><a href="system.html">System Status</a></li>
        <li><a href="services.html">Services</a></li>
        <li><a href="logs.html">Logs</a></li>
        <li><a href="processes.html">Processes</a></li> <!-- 追加 -->
    </ul>
</nav>
```

---

## ✅ テスト実行

### Backend テスト

```bash
# ユニットテスト実行
pytest tests/test_processes.py -v

# カバレッジ確認
pytest tests/test_processes.py --cov=backend/api/routes/processes --cov-report=html

# Wrapper テスト実行
cd wrappers/test
bash test-adminui-processes.sh
```

### Frontend テスト

1. **手動テスト**:
   - ブラウザで `http://localhost:8000/processes.html` にアクセス
   - 各フィルタの動作確認
   - ソート機能の確認
   - 自動更新の確認

2. **クロスブラウザテスト**:
   - Chrome
   - Firefox
   - Safari

---

## 📝 完了チェックリスト

### Backend実装

- [ ] BE-1: sudo_wrapper.py メソッド追加
- [ ] BE-2: adminui-processes.sh 作成
- [ ] BE-3: processes.py 作成
- [ ] BE-4: API ルーター登録
- [ ] BE-5: ユニットテスト作成
- [ ] BE-6: Wrapper テスト作成
- [ ] pytest 全通過
- [ ] カバレッジ 85% 以上
- [ ] bandit セキュリティチェック通過

### Frontend実装

- [ ] FE-1: processes.html 作成
- [ ] FE-2: processes.js 作成
- [ ] FE-3: CSS スタイリング
- [ ] FE-4: ナビゲーション追加
- [ ] FE-5: ブラウザテスト完了
- [ ] 各機能の動作確認
- [ ] レスポンシブデザイン確認

### レビュー

- [ ] security-checker によるセキュリティレビュー
- [ ] code-reviewer によるコードレビュー
- [ ] test-designer によるテストレビュー
- [ ] arch-reviewer による設計レビュー

---

## 🚀 次のステップ

1. backend-impl が実装完了
2. frontend-impl が実装完了
3. security-checker がセキュリティレビュー
4. code-reviewer がコードレビュー
5. test-designer がテストレビュー
6. team-lead が最終承認
7. Git commit & Push
8. CI/CD パイプライン実行

---

**参照**:
- [processes-module-design.md](./processes-module-design.md) - 詳細設計書
- [CLAUDE.md](/mnt/LinuxHDD/Linux-Management-Systm/CLAUDE.md) - セキュリティ原則

# Running Processes モジュール アーキテクチャ設計書

**作成日**: 2026-02-06
**担当**: arch-reviewer (ClaudeCode)
**対象**: Running Processes モジュール v0.2
**セキュリティレベル**: MEDIUM-HIGH

---

## 📋 目次

1. [概要](#概要)
2. [アーキテクチャ全体図](#アーキテクチャ全体図)
3. [コンポーネント設計](#コンポーネント設計)
4. [データフロー設計](#データフロー設計)
5. [セキュリティ設計](#セキュリティ設計)
6. [エラーハンドリング戦略](#エラーハンドリング戦略)
7. [パフォーマンス考慮事項](#パフォーマンス考慮事項)
8. [既存パターンとの一貫性](#既存パターンとの一貫性)
9. [実装ガイドライン](#実装ガイドライン)
10. [レビューチェックリスト](#レビューチェックリスト)

---

## 概要

### 目的

Linux システム上で実行中のプロセスを安全に閲覧・管理するための WebUI モジュール。

### スコープ

**Phase 1 (v0.2) - 参照系**:
- ✅ プロセス一覧取得 (ps/top)
- ✅ プロセス詳細表示
- ✅ プロセスフィルタリング (ユーザー、CPU/メモリ使用率)
- ✅ プロセスソート (CPU/MEM/PID/TIME)

**Phase 2 (v0.3) - 操作系**:
- ⚠️ プロセス停止 (SIGTERM) - allowlist 対象のみ
- ⚠️ プロセス強制停止 (SIGKILL) - 承認フロー必須
- ⚠️ プロセス優先度変更 (nice/renice) - 制限付き

**Phase 3 (v0.4) - 高度な機能**:
- ⚠️ リソース制限 (cgroup)
- ⚠️ プロセスツリー表示
- ⚠️ リアルタイム監視

**本設計書の範囲**: Phase 1 (参照系のみ)

### セキュリティリスク評価

| 機能 | リスクレベル | 理由 |
|------|------------|------|
| プロセス一覧取得 | LOW | 読み取り専用、root不要 |
| プロセス詳細表示 | LOW | 読み取り専用、情報漏洩可能性あり |
| プロセス停止 | **HIGH** | サービス停止、DoS可能 |
| プロセス強制停止 | **CRITICAL** | データ損失リスク |
| プロセス優先度変更 | MEDIUM | パフォーマンス影響 |

**Phase 1 のセキュリティ目標**: 情報漏洩防止、root権限不要

---

## アーキテクチャ全体図

```
┌─────────────────────────────────────────────────────────────┐
│                      Web Browser (Client)                    │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  processes.html + processes.js                       │    │
│  │  - プロセステーブル表示                                │    │
│  │  - ソート・フィルタリング UI                           │    │
│  │  - リアルタイム更新 (polling)                          │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────┬───────────────────────────────────────┘
                      │ HTTPS (JSON)
                      │ GET /api/v1/processes?sort=cpu&limit=100
                      ↓
┌─────────────────────────────────────────────────────────────┐
│                    FastAPI Backend                           │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  backend/api/routes/processes.py                     │    │
│  │  - 入力検証 (Pydantic)                                │    │
│  │  - 認証・認可 (require_permission("read:processes"))  │    │
│  │  - 監査ログ記録                                       │    │
│  │  - sudo_wrapper 呼び出し                              │    │
│  └────────────────────┬────────────────────────────────┘    │
└─────────────────────┬┴────────────────────────────────────┘
                      │
                      │ sudo_wrapper.get_processes(filters)
                      ↓
┌─────────────────────────────────────────────────────────────┐
│               backend/core/sudo_wrapper.py                   │
│  - _execute() でラッパースクリプト呼び出し                     │
│  - JSON レスポンスパース                                      │
│  - エラーハンドリング                                         │
└────────────────────┬────────────────────────────────────────┘
                     │
                     │ sudo /usr/local/sbin/adminui-processes.sh
                     │      --sort=cpu --limit=100
                     ↓
┌─────────────────────────────────────────────────────────────┐
│            wrappers/adminui-processes.sh                     │
│  ┌─────────────────────────────────────────────────────┐    │
│  │  1. 入力検証（特殊文字、範囲チェック）                │    │
│  │  2. ps コマンド実行（配列渡し）                       │    │
│  │  3. JSON 整形                                        │    │
│  │  4. 監査ログ出力 (logger)                             │    │
│  └─────────────────────────────────────────────────────┘    │
└─────────────────────────────────────────────────────────────┘
                     │
                     │ ps aux / top -bn1
                     ↓
              Linux Kernel (procfs)
```

---

## コンポーネント設計

### 1. Wrapper Script: `adminui-processes.sh`

**ファイル**: `/usr/local/sbin/adminui-processes.sh` (本番) / `wrappers/adminui-processes.sh` (開発)

#### 責務

- プロセス情報の安全な取得
- 入力パラメータの厳格な検証
- JSON 形式での出力
- 監査ログの記録

#### 入力パラメータ

```bash
# 呼び出し例
sudo /usr/local/sbin/adminui-processes.sh \
  --sort=cpu \
  --limit=100 \
  --filter-user=www-data \
  --min-cpu=10.0
```

| パラメータ | 型 | デフォルト | 必須 | 説明 |
|-----------|---|-----------|------|------|
| `--sort` | enum | `cpu` | No | ソートキー: `cpu`, `mem`, `pid`, `time` |
| `--limit` | int | `100` | No | 取得件数 (1-1000) |
| `--filter-user` | string | - | No | ユーザー名フィルタ (allowlist検証) |
| `--min-cpu` | float | `0.0` | No | 最小CPU使用率 (0.0-100.0) |
| `--min-mem` | float | `0.0` | No | 最小メモリ使用率 (0.0-100.0) |

#### 出力形式 (JSON)

```json
{
  "status": "success",
  "total_processes": 256,
  "returned_processes": 100,
  "sort_by": "cpu",
  "filters": {
    "user": "www-data",
    "min_cpu": 10.0
  },
  "processes": [
    {
      "pid": 1234,
      "user": "www-data",
      "cpu_percent": 25.5,
      "mem_percent": 12.3,
      "vsz": 512000,
      "rss": 256000,
      "tty": "?",
      "stat": "Sl",
      "start": "Jan01",
      "time": "12:34:56",
      "command": "nginx: worker process"
    }
  ],
  "timestamp": "2026-02-06T12:34:56+00:00"
}
```

#### セキュリティ実装

```bash
# ===================================================================
# 禁止文字パターン
# ===================================================================
FORBIDDEN_CHARS='[;|&$()` ><*?{}[\]]'

# ===================================================================
# 許可ユーザーリスト（allowlist）
# ===================================================================
ALLOWED_USERS=(
    "root"
    "www-data"
    "postgres"
    "redis"
    "nginx"
    "adminui"
)

# ===================================================================
# 許可ソートキー（allowlist）
# ===================================================================
ALLOWED_SORTS=(
    "cpu"
    "mem"
    "pid"
    "time"
)

# ===================================================================
# 入力検証関数
# ===================================================================
validate_sort_key() {
    local sort="$1"
    for allowed in "${ALLOWED_SORTS[@]}"; do
        if [ "$sort" = "$allowed" ]; then
            return 0
        fi
    done
    error "Invalid sort key: $sort"
    return 1
}

validate_user() {
    local user="$1"

    # 特殊文字チェック
    if [[ "$user" =~ $FORBIDDEN_CHARS ]]; then
        error "Forbidden character in user name"
        return 1
    fi

    # allowlist チェック
    for allowed in "${ALLOWED_USERS[@]}"; do
        if [ "$user" = "$allowed" ]; then
            return 0
        fi
    done

    error "User not in allowlist: $user"
    return 1
}
```

#### コマンド実行

```bash
# ✅ 安全なコマンド実行（配列渡し）
if [ -n "$FILTER_USER" ]; then
    # ユーザーフィルタあり
    OUTPUT=$(ps aux --user "$FILTER_USER" --sort=-%cpu 2>&1)
else
    # 全プロセス
    OUTPUT=$(ps aux --sort=-%cpu 2>&1)
fi
```

---

### 2. Backend Core: `sudo_wrapper.py`

**ファイル**: `backend/core/sudo_wrapper.py`

#### 新規メソッド追加

```python
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

---

### 3. API Route: `processes.py`

**ファイル**: `backend/api/routes/processes.py`

#### エンドポイント設計

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

---

### 4. Frontend: `processes.html` + `processes.js`

**ファイル**: `frontend/processes.html`, `frontend/js/processes.js`

#### UI設計

```html
<!-- processes.html -->
<!DOCTYPE html>
<html lang="ja">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>Running Processes - Linux Management System</title>
    <link rel="stylesheet" href="css/style.css">
</head>
<body>
    <div class="container">
        <h1>🔄 Running Processes</h1>

        <!-- フィルタリング・ソート UI -->
        <div class="controls">
            <div class="control-group">
                <label for="sortBy">Sort by:</label>
                <select id="sortBy">
                    <option value="cpu" selected>CPU Usage</option>
                    <option value="mem">Memory Usage</option>
                    <option value="pid">PID</option>
                    <option value="time">Run Time</option>
                </select>
            </div>

            <div class="control-group">
                <label for="filterUser">User:</label>
                <select id="filterUser">
                    <option value="">All Users</option>
                    <option value="root">root</option>
                    <option value="www-data">www-data</option>
                    <option value="postgres">postgres</option>
                    <option value="redis">redis</option>
                </select>
            </div>

            <div class="control-group">
                <label for="minCpu">Min CPU (%):</label>
                <input type="number" id="minCpu" min="0" max="100" step="1" value="0">
            </div>

            <div class="control-group">
                <label for="minMem">Min Memory (%):</label>
                <input type="number" id="minMem" min="0" max="100" step="1" value="0">
            </div>

            <button id="refreshBtn">🔄 Refresh</button>
            <button id="autoRefreshBtn">⏸️ Auto-refresh (5s)</button>
        </div>

        <!-- プロセステーブル -->
        <div class="table-container">
            <table id="processTable">
                <thead>
                    <tr>
                        <th>PID</th>
                        <th>User</th>
                        <th>CPU %</th>
                        <th>MEM %</th>
                        <th>VSZ (KB)</th>
                        <th>RSS (KB)</th>
                        <th>TTY</th>
                        <th>STAT</th>
                        <th>START</th>
                        <th>TIME</th>
                        <th>Command</th>
                    </tr>
                </thead>
                <tbody id="processTableBody">
                    <tr>
                        <td colspan="11" class="loading">Loading...</td>
                    </tr>
                </tbody>
            </table>
        </div>

        <div id="status" class="status"></div>
    </div>

    <script src="js/processes.js"></script>
</body>
</html>
```

#### JavaScript 実装

```javascript
// processes.js
class ProcessManager {
    constructor() {
        this.apiBaseUrl = '/api/v1/processes';
        this.autoRefreshInterval = null;
        this.isAutoRefresh = false;

        this.init();
    }

    init() {
        // イベントリスナー登録
        document.getElementById('refreshBtn').addEventListener('click', () => this.loadProcesses());
        document.getElementById('autoRefreshBtn').addEventListener('click', () => this.toggleAutoRefresh());

        // フィルタ変更時に自動更新
        ['sortBy', 'filterUser', 'minCpu', 'minMem'].forEach(id => {
            document.getElementById(id).addEventListener('change', () => {
                if (!this.isAutoRefresh) {
                    this.loadProcesses();
                }
            });
        });

        // 初回読み込み
        this.loadProcesses();
    }

    async loadProcesses() {
        const sortBy = document.getElementById('sortBy').value;
        const filterUser = document.getElementById('filterUser').value;
        const minCpu = parseFloat(document.getElementById('minCpu').value) || 0.0;
        const minMem = parseFloat(document.getElementById('minMem').value) || 0.0;

        // クエリパラメータ構築
        const params = new URLSearchParams({
            sort_by: sortBy,
            limit: 100,
            min_cpu: minCpu,
            min_mem: minMem,
        });

        if (filterUser) {
            params.append('filter_user', filterUser);
        }

        try {
            const response = await fetch(`${this.apiBaseUrl}?${params}`, {
                headers: {
                    'Authorization': `Bearer ${localStorage.getItem('token')}`,
                },
            });

            if (!response.ok) {
                throw new Error(`HTTP ${response.status}: ${response.statusText}`);
            }

            const data = await response.json();
            this.renderProcessTable(data);
            this.showStatus(`✅ Loaded ${data.returned_processes} processes`, 'success');
        } catch (error) {
            console.error('Failed to load processes:', error);
            this.showStatus(`❌ Error: ${error.message}`, 'error');
        }
    }

    renderProcessTable(data) {
        const tbody = document.getElementById('processTableBody');
        tbody.innerHTML = '';

        if (data.processes.length === 0) {
            tbody.innerHTML = '<tr><td colspan="11" class="no-data">No processes found</td></tr>';
            return;
        }

        data.processes.forEach(proc => {
            const row = document.createElement('tr');

            // CPU使用率が高い行をハイライト
            if (proc.cpu_percent > 50) {
                row.classList.add('high-cpu');
            }

            row.innerHTML = `
                <td>${proc.pid}</td>
                <td>${proc.user}</td>
                <td class="cpu-usage">${proc.cpu_percent.toFixed(1)}%</td>
                <td class="mem-usage">${proc.mem_percent.toFixed(1)}%</td>
                <td>${proc.vsz.toLocaleString()}</td>
                <td>${proc.rss.toLocaleString()}</td>
                <td>${proc.tty}</td>
                <td>${proc.stat}</td>
                <td>${proc.start}</td>
                <td>${proc.time}</td>
                <td class="command">${this.escapeHtml(proc.command)}</td>
            `;

            tbody.appendChild(row);
        });
    }

    toggleAutoRefresh() {
        const btn = document.getElementById('autoRefreshBtn');

        if (this.isAutoRefresh) {
            // 自動更新停止
            clearInterval(this.autoRefreshInterval);
            this.autoRefreshInterval = null;
            this.isAutoRefresh = false;
            btn.textContent = '▶️ Auto-refresh (5s)';
            this.showStatus('Auto-refresh stopped', 'info');
        } else {
            // 自動更新開始
            this.autoRefreshInterval = setInterval(() => this.loadProcesses(), 5000);
            this.isAutoRefresh = true;
            btn.textContent = '⏸️ Auto-refresh (5s)';
            this.showStatus('Auto-refresh started', 'info');
            this.loadProcesses();
        }
    }

    showStatus(message, type) {
        const statusDiv = document.getElementById('status');
        statusDiv.textContent = message;
        statusDiv.className = `status ${type}`;

        setTimeout(() => {
            statusDiv.textContent = '';
            statusDiv.className = 'status';
        }, 3000);
    }

    escapeHtml(text) {
        const div = document.createElement('div');
        div.textContent = text;
        return div.innerHTML;
    }
}

// ページ読み込み時に初期化
document.addEventListener('DOMContentLoaded', () => {
    new ProcessManager();
});
```

---

## データフロー設計

### シーケンス図: プロセス一覧取得

```
User Browser          API Gateway         processes.py         sudo_wrapper.py      adminui-processes.sh     ps/top
    │                      │                    │                     │                      │                    │
    │  GET /processes     │                    │                     │                      │                    │
    │  ?sort=cpu&limit=100│                    │                     │                      │                    │
    ├─────────────────────>│                    │                     │                      │                    │
    │                      │  require_permission│                     │                      │                    │
    │                      │  ("read:processes")│                     │                      │                    │
    │                      ├───────────────────>│                     │                      │                    │
    │                      │                    │ get_processes()     │                      │                    │
    │                      │                    ├────────────────────>│                      │                    │
    │                      │                    │                     │ _execute(            │                    │
    │                      │                    │                     │   "adminui-processes.sh",│                 │
    │                      │                    │                     │   ["--sort=cpu", "--limit=100"]│          │
    │                      │                    │                     ├─────────────────────>│                    │
    │                      │                    │                     │                      │ 入力検証            │
    │                      │                    │                     │                      │ (特殊文字、範囲)    │
    │                      │                    │                     │                      │                    │
    │                      │                    │                     │                      │ ps aux --sort=-%cpu│
    │                      │                    │                     │                      ├───────────────────>│
    │                      │                    │                     │                      │                    │
    │                      │                    │                     │                      │  プロセス情報       │
    │                      │                    │                     │                      │<───────────────────┤
    │                      │                    │                     │                      │                    │
    │                      │                    │                     │                      │ JSON整形            │
    │                      │                    │                     │                      │ logger出力          │
    │                      │                    │                     │  JSON response       │                    │
    │                      │                    │                     │<─────────────────────┤                    │
    │                      │                    │  Dict[str, Any]     │                      │                    │
    │                      │                    │<────────────────────┤                      │                    │
    │                      │  ProcessListResponse│                     │                      │                    │
    │                      │<───────────────────┤                     │                      │                    │
    │  JSON Response       │                    │                     │                      │                    │
    │<─────────────────────┤                    │                     │                      │                    │
    │                      │                    │                     │                      │                    │
```

### エラーフロー

```
User Browser          API Gateway         processes.py         sudo_wrapper.py      adminui-processes.sh
    │                      │                    │                     │                      │
    │  GET /processes     │                    │                     │                      │
    │  ?sort=invalid      │                    │                     │                      │
    ├─────────────────────>│                    │                     │                      │
    │                      │  Pydantic検証       │                     │                      │
    │                      │  ❌ 400 Bad Request │                     │                      │
    │<─────────────────────┤                    │                     │                      │
    │                      │                    │                     │                      │
    │  GET /processes     │                    │                     │                      │
    │  ?filter_user=hacker│ ; rm -rf /         │                     │                      │
    ├─────────────────────>│                    │                     │                      │
    │                      │  Pydantic検証       │                     │                      │
    │                      │  (regex mismatch)  │                     │                      │
    │                      │  ❌ 400 Bad Request │                     │                      │
    │<─────────────────────┤                    │                     │                      │
    │                      │                    │                     │                      │
    │  GET /processes     │                    │                     │                      │
    │  ?filter_user=hacker│                    │                     │                      │
    ├─────────────────────>│                    │                     │                      │
    │                      │                    │ get_processes()     │                      │
    │                      │                    ├────────────────────>│                      │
    │                      │                    │                     │ _execute()           │
    │                      │                    │                     ├─────────────────────>│
    │                      │                    │                     │                      │ allowlist検証
    │                      │                    │                     │                      │ ❌ User not allowed
    │                      │                    │                     │                      │ logger: SECURITY
    │                      │                    │                     │  {"status": "error", │
    │                      │                    │                     │   "message": "User not allowed"}
    │                      │                    │                     │<─────────────────────┤
    │                      │                    │  audit_log.record() │                      │
    │                      │                    │  (status="denied")  │                      │
    │                      │  ❌ 403 Forbidden   │                     │                      │
    │<─────────────────────┤                    │                     │                      │
```

---

## セキュリティ設計

### CLAUDE.md セキュリティ原則への準拠

#### 1. Allowlist First ✅

```bash
# wrappers/adminui-processes.sh
ALLOWED_USERS=(
    "root"
    "www-data"
    "postgres"
    "redis"
    "nginx"
    "adminui"
)

ALLOWED_SORTS=(
    "cpu"
    "mem"
    "pid"
    "time"
)
```

#### 2. Deny by Default ✅

```bash
# デフォルトで全拒否
SERVICE_ALLOWED=false

# allowlist に存在する場合のみ許可
for allowed in "${ALLOWED_USERS[@]}"; do
    if [ "$FILTER_USER" = "$allowed" ]; then
        SERVICE_ALLOWED=true
        break
    fi
done

if [ "$SERVICE_ALLOWED" = false ]; then
    error "User not in allowlist: $FILTER_USER"
    exit 1
fi
```

#### 3. Shell禁止 ✅

```bash
# ✅ 配列渡し（shell展開なし）
OUTPUT=$(ps aux --user "$FILTER_USER" --sort=-%cpu 2>&1)

# ❌ 絶対禁止
# OUTPUT=$(ps aux --user $FILTER_USER --sort=-$SORT_BY)  # 危険
```

#### 4. sudo最小化 ✅

- **Phase 1**: root権限不要（`ps aux` はユーザー権限で実行可能）
- **Phase 2**: プロセス停止時のみ sudo 経由

```python
# sudo_wrapper.py
def get_processes(...):
    # Phase 1: sudo 不要（情報取得のみ）
    return self._execute("adminui-processes.sh", args, timeout=10)
```

#### 5. 監査証跡 ✅

```python
# API Route
audit_log.record(
    operation="process_list",
    user_id=current_user.user_id,
    target="system",
    status="success",
    details={
        "sort_by": sort_by,
        "limit": limit,
        "filter_user": filter_user,
        "returned_processes": result.get("returned_processes", 0),
    },
)
```

```bash
# Wrapper Script
log "Process list requested: sort=$SORT_BY, limit=$LIMIT, user=$FILTER_USER, caller=${SUDO_USER:-$USER}"
```

### 入力検証の多層防御

| レイヤー | 検証内容 | 実装場所 |
|---------|---------|---------|
| **Frontend** | - クライアント側検証<br>- ドロップダウン選択（allowlist UI）<br>- 数値範囲チェック (0-100) | `processes.js` |
| **API (Pydantic)** | - 型検証 (int, float, str)<br>- 正規表現マッチ (`^[a-zA-Z0-9_-]+$`)<br>- 範囲検証 (ge=0, le=100) | `processes.py` |
| **Wrapper** | - 特殊文字検出<br>- allowlist 検証<br>- 範囲再検証 | `adminui-processes.sh` |

### 情報漏洩対策

**Phase 1 での懸念事項**:
- プロセスコマンドライン引数に機密情報が含まれる可能性
- 他ユーザーのプロセス情報の閲覧

**対策**:

1. **コマンドライン引数の切り詰め**

```bash
# 長すぎるコマンドを切り詰め（最大100文字）
COMMAND=$(echo "$COMMAND" | cut -c1-100)
if [ ${#COMMAND} -eq 100 ]; then
    COMMAND="${COMMAND}..."
fi
```

2. **権限ベースのフィルタリング**

```python
# 将来的な実装（Phase 2）
if current_user.role != "admin":
    # 一般ユーザーは自分のプロセスのみ閲覧可能
    filter_user = current_user.username
```

3. **機密情報のマスキング**

```bash
# パスワード、トークンなどを含むコマンドをマスキング
COMMAND=$(echo "$COMMAND" | sed 's/password=[^ ]*/password=***/g')
COMMAND=$(echo "$COMMAND" | sed 's/token=[^ ]*/token=***/g')
```

---

## エラーハンドリング戦略

### エラー分類

| エラー種別 | HTTPステータス | 監査ログ | ユーザーメッセージ |
|-----------|---------------|---------|-------------------|
| **入力検証エラー** | 400 Bad Request | `attempt` | "Invalid input: ..." |
| **認証エラー** | 401 Unauthorized | `denied` | "Authentication required" |
| **認可エラー** | 403 Forbidden | `denied` | "Permission denied" |
| **allowlist 拒否** | 403 Forbidden | `denied` | "User not allowed: ..." |
| **ラッパー実行失敗** | 500 Internal Server Error | `failure` | "System error" |
| **タイムアウト** | 504 Gateway Timeout | `failure` | "Request timeout" |

### エラーハンドリングコード

```python
# processes.py
try:
    result = sudo_wrapper.get_processes(...)

    if result.get("status") == "error":
        # ラッパーレベルのエラー（allowlist拒否など）
        audit_log.record(operation="process_list", status="denied", ...)
        raise HTTPException(status_code=403, detail=result.get("message"))

    # 成功
    audit_log.record(operation="process_list", status="success", ...)
    return ProcessListResponse(**result)

except SudoWrapperError as e:
    # システムレベルのエラー
    audit_log.record(operation="process_list", status="failure", ...)
    raise HTTPException(status_code=500, detail="System error")

except Exception as e:
    # 予期しないエラー
    logger.exception("Unexpected error in process list")
    audit_log.record(operation="process_list", status="failure", ...)
    raise HTTPException(status_code=500, detail="Unexpected error")
```

### タイムアウト設定

```python
# sudo_wrapper.py
def get_processes(...) -> Dict[str, Any]:
    # プロセス一覧取得は軽量なので10秒でタイムアウト
    return self._execute("adminui-processes.sh", args, timeout=10)
```

---

## パフォーマンス考慮事項

### 大量プロセス時の対応

**問題**: 数千プロセスが実行中の場合、レスポンスが遅延・肥大化

**対策**:

1. **limit パラメータの強制**

```python
# API Route
limit: int = Query(100, ge=1, le=1000)
```

- デフォルト: 100件
- 最大: 1000件（それ以上は拒否）

2. **ページネーション（Phase 2で実装）**

```python
# 将来的な実装
offset: int = Query(0, ge=0)
limit: int = Query(100, ge=1, le=1000)
```

3. **キャッシング（Phase 3で実装）**

```python
# Redis キャッシュ（TTL: 5秒）
cache_key = f"processes:{sort_by}:{filter_user}:{min_cpu}:{min_mem}"
cached_result = redis_client.get(cache_key)
if cached_result:
    return cached_result
```

### リアルタイム更新の効率化

**Frontend 側のポーリング最適化**:

```javascript
// processes.js
toggleAutoRefresh() {
    if (this.isAutoRefresh) {
        // 5秒間隔でポーリング（調整可能）
        this.autoRefreshInterval = setInterval(() => this.loadProcesses(), 5000);
    }
}
```

**将来的な改善案（Phase 3）**:
- WebSocket による push 型更新
- Server-Sent Events (SSE) の利用

---

## 既存パターンとの一貫性

### コード規約の準拠

| 項目 | 既存パターン | 本設計での適用 |
|------|------------|---------------|
| **API Prefix** | `/api/v1/` | ✅ `/api/v1/processes` |
| **Router Prefix** | `router = APIRouter(prefix="/xxx", tags=["xxx"])` | ✅ `prefix="/processes", tags=["processes"]` |
| **認可** | `Depends(require_permission("read:xxx"))` | ✅ `require_permission("read:processes")` |
| **監査ログ** | `audit_log.record(operation, user_id, target, status, details)` | ✅ 全フローで実装 |
| **Wrapper呼び出し** | `sudo_wrapper._execute(script_name, args)` | ✅ `sudo_wrapper.get_processes()` |
| **JSON出力** | Bash: `echo "{...}"` | ✅ 同一形式 |
| **エラーレスポンス** | `{"status": "error", "message": "..."}` | ✅ 同一形式 |
| **ログ記録** | Bash: `logger -t adminui-xxx` | ✅ `logger -t adminui-processes` |

### ファイル配置の一貫性

```
backend/
├── api/
│   └── routes/
│       ├── system.py       # 既存
│       ├── services.py     # 既存
│       ├── logs.py         # 既存
│       └── processes.py    # ✅ 新規（同じパターン）
└── core/
    └── sudo_wrapper.py     # ✅ get_processes() メソッド追加

wrappers/
├── adminui-status.sh       # 既存
├── adminui-service-restart.sh  # 既存
├── adminui-logs.sh         # 既存
└── adminui-processes.sh    # ✅ 新規（同じパターン）

frontend/
├── index.html              # 既存
├── system.html             # 既存
├── services.html           # 既存
├── logs.html               # 既存
└── processes.html          # ✅ 新規

frontend/js/
├── system.js               # 既存
├── services.js             # 既存
├── logs.js                 # 既存
└── processes.js            # ✅ 新規
```

---

## 実装ガイドライン

### backend-impl (Backend実装者) 向け

#### タスク1: `sudo_wrapper.py` にメソッド追加

**ファイル**: `backend/core/sudo_wrapper.py`

```python
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
        filter_user: ユーザー名フィルタ
        min_cpu: 最小CPU使用率
        min_mem: 最小メモリ使用率

    Returns:
        プロセス情報の辞書
    """
    args = [f"--sort={sort_by}", f"--limit={limit}"]
    if filter_user:
        args.append(f"--filter-user={filter_user}")
    if min_cpu > 0.0:
        args.append(f"--min-cpu={min_cpu}")
    if min_mem > 0.0:
        args.append(f"--min-mem={min_mem}")

    return self._execute("adminui-processes.sh", args, timeout=10)
```

#### タスク2: `processes.py` 作成

**ファイル**: `backend/api/routes/processes.py`

- 上記「コンポーネント設計 > 3. API Route」のコードを実装
- Pydantic モデル定義
- エンドポイント実装
- エラーハンドリング
- 監査ログ記録

#### タスク3: `adminui-processes.sh` 作成

**ファイル**: `wrappers/adminui-processes.sh`

- 上記「コンポーネント設計 > 1. Wrapper Script」のコードを実装
- 入力検証（特殊文字、allowlist、範囲）
- ps コマンド実行
- JSON 整形
- logger 出力

#### タスク4: API ルーターに登録

**ファイル**: `backend/api/routes/__init__.py`

```python
from .processes import router as processes_router

# FastAPI アプリに登録
app.include_router(processes_router, prefix="/api/v1")
```

#### テスト

```bash
# pytest実行
pytest tests/test_processes.py -v

# カバレッジ確認
pytest tests/test_processes.py --cov=backend/api/routes/processes --cov-report=html
```

---

### frontend-impl (Frontend実装者) 向け

#### タスク1: `processes.html` 作成

**ファイル**: `frontend/processes.html`

- 上記「コンポーネント設計 > 4. Frontend」の HTML を実装
- フィルタリング UI
- プロセステーブル
- ステータス表示

#### タスク2: `processes.js` 作成

**ファイル**: `frontend/js/processes.js`

- 上記「コンポーネント設計 > 4. Frontend」の JavaScript を実装
- API 呼び出し
- テーブルレンダリング
- 自動更新機能

#### タスク3: CSS スタイリング

**ファイル**: `frontend/css/style.css`

```css
/* プロセステーブルのスタイル */
#processTable {
    width: 100%;
    border-collapse: collapse;
}

#processTable th {
    background-color: #333;
    color: white;
    padding: 10px;
    text-align: left;
}

#processTable td {
    padding: 8px;
    border-bottom: 1px solid #ddd;
}

#processTable tr:hover {
    background-color: #f5f5f5;
}

/* 高CPU使用率のハイライト */
#processTable tr.high-cpu {
    background-color: #fff3cd;
}

/* コマンド列の幅制限 */
#processTable td.command {
    max-width: 300px;
    overflow: hidden;
    text-overflow: ellipsis;
    white-space: nowrap;
}
```

#### テスト

- 各ブラウザでの動作確認（Chrome, Firefox, Safari）
- レスポンシブデザインの確認
- エラーハンドリングの確認

---

## レビューチェックリスト

### セキュリティレビュー（security-checker）

- [ ] **Allowlist First**: 全入力が allowlist で検証されているか？
- [ ] **Deny by Default**: デフォルトで拒否されているか？
- [ ] **Shell禁止**: `shell=True`, `os.system()`, `eval()` が使用されていないか？
- [ ] **特殊文字検証**: `;`, `|`, `&`, `$`, etc. が拒否されているか?
- [ ] **sudo最小化**: Phase 1 では sudo 不要、Phase 2 でのみ使用しているか？
- [ ] **監査ログ**: 全操作が記録されているか？（attempt, success, denied, failure）
- [ ] **情報漏洩**: 機密情報がログ・レスポンスに含まれていないか？
- [ ] **タイムアウト**: 長時間実行を防止するタイムアウトが設定されているか？

### コードレビュー（code-reviewer）

- [ ] **型ヒント**: 全関数に型ヒントが付与されているか？
- [ ] **docstring**: 全関数に docstring が記載されているか？
- [ ] **エラーハンドリング**: 全エラーケースが処理されているか？
- [ ] **ログ記録**: 適切なレベルでログが記録されているか？（info, warning, error）
- [ ] **Pydantic モデル**: API リクエスト・レスポンスが Pydantic で定義されているか？
- [ ] **正規表現**: 入力検証の正規表現が適切か？
- [ ] **既存パターン**: 既存コードと一貫性があるか？

### テストレビュー（test-designer）

- [ ] **正常系テスト**: 全機能の正常系がテストされているか？
- [ ] **異常系テスト**: 入力検証エラーがテストされているか？
- [ ] **セキュリティテスト**: 特殊文字、allowlist 拒否がテストされているか？
- [ ] **カバレッジ**: 目標カバレッジ（85%以上）に到達しているか？
- [ ] **Wrapper テスト**: Bash スクリプトの全パターンがテストされているか？

### アーキテクチャレビュー（arch-reviewer = 本ドキュメント作成者）

- [ ] **3層アーキテクチャ**: Wrapper → sudo_wrapper → API の構造が守られているか？
- [ ] **責務分離**: 各コンポーネントが明確な責務を持っているか？
- [ ] **スケーラビリティ**: 大量プロセス時にパフォーマンス問題が発生しないか？
- [ ] **拡張性**: Phase 2, Phase 3 への拡張が容易か？
- [ ] **保守性**: コードが読みやすく、保守しやすいか？

---

## まとめ

### 設計のハイライト

1. **セキュリティファースト**: CLAUDE.md の5原則を完全遵守
2. **既存パターン継承**: system.py, services.py, logs.py と完全一貫性
3. **段階的実装**: Phase 1 (参照) → Phase 2 (操作) → Phase 3 (高度)
4. **多層防御**: Frontend → API → Wrapper での多重検証
5. **監査証跡**: 全操作を記録（attempt, success, denied, failure）

### 次のステップ

1. **backend-impl**: `sudo_wrapper.py`, `processes.py`, `adminui-processes.sh` 実装
2. **frontend-impl**: `processes.html`, `processes.js` 実装
3. **test-designer**: テストケース作成（正常系・異常系・セキュリティ）
4. **security-checker**: セキュリティレビュー・脆弱性検証
5. **code-reviewer**: コードレビュー・品質確認
6. **CI/CD**: GitHub Actions での自動テスト

### 参照ドキュメント

- [CLAUDE.md](/mnt/LinuxHDD/Linux-Management-Systm/CLAUDE.md) - セキュリティ原則
- [README.md](/mnt/LinuxHDD/Linux-Management-Systm/README.md) - プロジェクト概要
- [要件定義書](/mnt/LinuxHDD/Linux-Management-Systm/docs/要件定義書_詳細設計仕様書.md) - 要件詳細

---

**承認**: 本設計書は team-lead の承認後、実装フェーズに移行します。

**変更履歴**:
- 2026-02-06: 初版作成（arch-reviewer）

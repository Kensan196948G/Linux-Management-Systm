#!/bin/bash
# Conflict Prevention - 並列実行時のコンフリクト防止

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_DIR="$PROJECT_ROOT/.workflow-locks"

mkdir -p "$LOCK_DIR"

# ログ出力
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] [CONFLICT-PREVENTION] $*" | tee -a "$PROJECT_ROOT/workflow.log"
}

# ===================================================================
# ファイルロック取得
# ===================================================================
acquire_lock() {
    local file_path="$1"
    local agent_name="$2"
    local timeout="${3:-30}"  # デフォルト30秒

    local lock_file="$LOCK_DIR/$(echo "$file_path" | tr '/' '_').lock"
    local start_time=$(date +%s)

    log "🔒 Attempting to acquire lock: $file_path (agent: $agent_name)"

    while true; do
        # ロックファイルが存在しない場合、作成
        if mkdir "$lock_file" 2>/dev/null; then
            echo "$agent_name:$$:$(date -Iseconds)" > "$lock_file/owner"
            log "✅ Lock acquired: $file_path by $agent_name"
            return 0
        fi

        # タイムアウトチェック
        local current_time=$(date +%s)
        local elapsed=$((current_time - start_time))

        if [ "$elapsed" -ge "$timeout" ]; then
            log "❌ Lock timeout: $file_path (waited $elapsed seconds)"
            log "   Lock owner: $(cat "$lock_file/owner" 2>/dev/null || echo 'unknown')"
            return 1
        fi

        log "⏳ Waiting for lock: $file_path (${elapsed}s elapsed)"
        sleep 1
    done
}

# ===================================================================
# ファイルロック解放
# ===================================================================
release_lock() {
    local file_path="$1"
    local agent_name="$2"

    local lock_file="$LOCK_DIR/$(echo "$file_path" | tr '/' '_').lock"

    if [ ! -d "$lock_file" ]; then
        log "⚠️ Warning: Lock does not exist: $file_path"
        return 0
    fi

    local owner=$(cat "$lock_file/owner" 2>/dev/null | cut -d':' -f1)

    if [ "$owner" != "$agent_name" ]; then
        log "❌ Error: Cannot release lock owned by $owner (you are $agent_name)"
        return 1
    fi

    rm -rf "$lock_file"
    log "🔓 Lock released: $file_path by $agent_name"
}

# ===================================================================
# 並列実行可能性チェック
# ===================================================================
can_run_parallel() {
    local agent1="$1"
    local agent2="$2"

    # 常時並列実行可能な組み合わせ
    local parallel_allowed=(
        "arch-reviewer:security"
        "arch-reviewer:qa"
        "security:qa"
    )

    for pair in "${parallel_allowed[@]}"; do
        if [[ "$pair" == "$agent1:$agent2" ]] || [[ "$pair" == "$agent2:$agent1" ]]; then
            return 0
        fi
    done

    # デフォルトは並列実行不可
    return 1
}

# ===================================================================
# ファイル競合チェック
# ===================================================================
check_file_conflict() {
    local agent_name="$1"
    shift
    local files=("$@")

    log "🔍 Checking file conflicts for $agent_name"
    log "   Target files: ${files[*]}"

    local conflicts=0

    for file in "${files[@]}"; do
        local lock_file="$LOCK_DIR/$(echo "$file" | tr '/' '_').lock"

        if [ -d "$lock_file" ]; then
            local owner=$(cat "$lock_file/owner" 2>/dev/null | cut -d':' -f1)
            log "⚠️ Conflict detected: $file is locked by $owner"
            conflicts=$((conflicts + 1))
        fi
    done

    if [ "$conflicts" -gt 0 ]; then
        log "❌ $conflicts file(s) are locked"
        return 1
    else
        log "✅ No conflicts detected"
        return 0
    fi
}

# ===================================================================
# 編集対象ファイルの登録
# ===================================================================
register_edit_target() {
    local agent_name="$1"
    shift
    local files=("$@")

    log "📝 Registering edit targets for $agent_name"

    local failed=0

    for file in "${files[@]}"; do
        if ! acquire_lock "$file" "$agent_name" 30; then
            log "❌ Failed to acquire lock: $file"
            failed=1
        fi
    done

    if [ "$failed" -ne 0 ]; then
        log "❌ Failed to register all files, releasing acquired locks"
        for file in "${files[@]}"; do
            release_lock "$file" "$agent_name" 2>/dev/null || true
        done
        return 1
    fi

    log "✅ All files registered successfully"
    return 0
}

# ===================================================================
# 編集完了・ロック解放
# ===================================================================
unregister_edit_target() {
    local agent_name="$1"
    shift
    local files=("$@")

    log "📝 Unregistering edit targets for $agent_name"

    for file in "${files[@]}"; do
        release_lock "$file" "$agent_name"
    done

    log "✅ All files unregistered"
}

# ===================================================================
# 競合回避ルールの適用
# ===================================================================
apply_conflict_rules() {
    local agent_name="$1"

    log "📋 Applying conflict prevention rules for $agent_name"

    case "$agent_name" in
        "code-implementer")
            # Backend 実装中は Backend ファイルをロック
            if [ -d "backend" ]; then
                log "   Rule: Lock backend/* during implementation"
            fi
            ;;

        "arch-reviewer"|"security"|"qa")
            # これらは常時並列実行可能
            log "   Rule: Parallel execution allowed"
            ;;

        *)
            log "   Rule: Default (sequential execution)"
            ;;
    esac
}

# ===================================================================
# 全ロックのクリーンアップ（緊急時用）
# ===================================================================
cleanup_all_locks() {
    log "🧹 Cleaning up all locks..."

    if [ -d "$LOCK_DIR" ]; then
        rm -rf "$LOCK_DIR"/*
        log "✅ All locks cleaned up"
    else
        log "ℹ️ No locks to clean up"
    fi
}

# ===================================================================
# ロック状態の表示
# ===================================================================
show_locks() {
    log "📊 Current lock status:"

    if [ ! -d "$LOCK_DIR" ] || [ -z "$(ls -A "$LOCK_DIR" 2>/dev/null)" ]; then
        log "   No active locks"
        return
    fi

    for lock_file in "$LOCK_DIR"/*.lock; do
        if [ -d "$lock_file" ]; then
            local file_name=$(basename "$lock_file" .lock | tr '_' '/')
            local owner=$(cat "$lock_file/owner" 2>/dev/null || echo "unknown")
            log "   🔒 $file_name - locked by $owner"
        fi
    done
}

# ===================================================================
# メインエントリーポイント
# ===================================================================
main() {
    local command="${1:-}"
    shift || true

    case "$command" in
        acquire)
            local file_path="$1"
            local agent_name="$2"
            acquire_lock "$file_path" "$agent_name"
            ;;

        release)
            local file_path="$1"
            local agent_name="$2"
            release_lock "$file_path" "$agent_name"
            ;;

        check)
            local agent_name="$1"
            shift
            check_file_conflict "$agent_name" "$@"
            ;;

        register)
            local agent_name="$1"
            shift
            register_edit_target "$agent_name" "$@"
            ;;

        unregister)
            local agent_name="$1"
            shift
            unregister_edit_target "$agent_name" "$@"
            ;;

        cleanup)
            cleanup_all_locks
            ;;

        status)
            show_locks
            ;;

        *)
            echo "Usage: $0 <command> [args...]"
            echo ""
            echo "Commands:"
            echo "  acquire <file> <agent>       - Acquire lock"
            echo "  release <file> <agent>       - Release lock"
            echo "  check <agent> <file...>      - Check conflicts"
            echo "  register <agent> <file...>   - Register and lock files"
            echo "  unregister <agent> <file...> - Unregister and unlock files"
            echo "  cleanup                      - Clean up all locks"
            echo "  status                       - Show current locks"
            exit 1
            ;;
    esac
}

main "$@"

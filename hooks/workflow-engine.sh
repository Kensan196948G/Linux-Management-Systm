#!/bin/bash
# Workflow Engine - SubAgent 連携制御

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"
LOCK_DIR="$PROJECT_ROOT/.workflow-locks"
STATE_FILE="$PROJECT_ROOT/.workflow-state.json"

# ロックディレクトリ作成
mkdir -p "$LOCK_DIR"

# ログ出力
log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*" | tee -a "$PROJECT_ROOT/workflow.log"
}

# ワークフロー状態の読み込み
load_state() {
    if [ -f "$STATE_FILE" ]; then
        cat "$STATE_FILE"
    else
        echo '{"current_phase":"idle","last_agent":"none","timestamp":""}'
    fi
}

# ワークフロー状態の保存
save_state() {
    local phase="$1"
    local agent="$2"
    cat > "$STATE_FILE" <<EOF
{
  "current_phase": "$phase",
  "last_agent": "$agent",
  "timestamp": "$(date -Iseconds)"
}
EOF
}

# ===================================================================
# Hook 1: on-spec-complete
# spec-planner が specs/* を生成 → arch-reviewer 起動
# ===================================================================
on_spec_complete() {
    log "🪝 Hook: on-spec-complete"

    # 前提チェック: specs/* が存在するか
    if [ ! -f "specs/overview.md" ] || [ ! -f "specs/requirements.md" ]; then
        log "❌ Error: specs/* not found"
        return 1
    fi

    log "✅ specs/* detected"
    log "🏗 Starting arch-reviewer..."

    # arch-reviewer 起動（実際の実装では SubAgent を呼び出す）
    # TODO: Claude Code SubAgent API 呼び出し
    save_state "arch-review" "arch-reviewer"

    log "📋 Next: arch-reviewer will review design"
}

# ===================================================================
# Hook 2: on-arch-approved
# arch-reviewer が PASS → code-implementer 起動
# ===================================================================
on_arch_approved() {
    log "🪝 Hook: on-arch-approved"

    # レビュー結果チェック
    local review_file="reviews/arch-review-latest.json"
    if [ ! -f "$review_file" ]; then
        log "❌ Error: arch-review result not found"
        return 1
    fi

    local result=$(jq -r '.result' "$review_file")

    if [ "$result" != "PASS" ]; then
        log "❌ Architecture review FAILED: $result"
        log "📋 Please fix blocking issues and re-submit"
        return 1
    fi

    log "✅ Architecture review PASSED"
    log "💻 Starting code-implementer..."

    save_state "implementation" "code-implementer"

    log "📋 Next: code-implementer will implement based on design/*"
}

# ===================================================================
# Hook 3: on-implementation-complete
# code-implementer が完了宣言 → code-reviewer 起動
# ===================================================================
on_implementation_complete() {
    log "🪝 Hook: on-implementation-complete"

    # 変更ファイルの確認
    if [ -z "$(git status --porcelain src/)" ]; then
        log "⚠️ Warning: No changes detected in src/"
    fi

    log "🕵️ Starting code-reviewer..."

    save_state "code-review" "code-reviewer"

    log "📋 Next: code-reviewer will review implementation"
}

# ===================================================================
# Hook 4: on-code-review-result
# code-reviewer が結果返却 → 分岐処理
# ===================================================================
on_code_review_result() {
    log "🪝 Hook: on-code-review-result"

    local review_file="reviews/code-review-latest.json"
    if [ ! -f "$review_file" ]; then
        log "❌ Error: code-review result not found"
        return 1
    fi

    local result=$(jq -r '.result' "$review_file")
    local blocking_count=$(jq '.blocking_issues | length' "$review_file")

    case "$result" in
        "FAIL")
            log "❌ Code review FAILED"
            log "🔄 Returning to code-implementer for fixes"
            save_state "implementation-rework" "code-implementer"
            ;;

        "PASS_WITH_WARNINGS")
            log "⚠️ Code review PASSED with warnings"
            log "📧 Notifying human for review"
            log "🧪 Starting test-designer (conditional)"
            save_state "test-design" "test-designer"
            ;;

        "PASS")
            log "✅ Code review PASSED"
            log "🧪 Starting test-designer..."
            save_state "test-design" "test-designer"
            ;;

        *)
            log "❌ Unknown review result: $result"
            return 1
            ;;
    esac
}

# ===================================================================
# Hook 5: on-test-design-complete
# test-designer が完了 → test-reviewer 起動
# ===================================================================
on_test_design_complete() {
    log "🪝 Hook: on-test-design-complete"

    if [ ! -f "tests/test_cases.md" ]; then
        log "❌ Error: tests/test_cases.md not found"
        return 1
    fi

    log "✅ Test cases designed"
    log "🔍 Starting test-reviewer..."

    save_state "test-review" "test-reviewer"

    log "📋 Next: test-reviewer will review test coverage"
}

# ===================================================================
# Hook 6: on-test-review-result
# test-reviewer が結果返却 → ci-specialist 起動
# ===================================================================
on_test_review_result() {
    log "🪝 Hook: on-test-review-result"

    local review_file="reviews/test-review-latest.json"
    if [ ! -f "$review_file" ]; then
        log "❌ Error: test-review result not found"
        return 1
    fi

    local result=$(jq -r '.result' "$review_file")

    if [ "$result" != "PASS" ]; then
        log "❌ Test review FAILED"
        log "🔄 Returning to test-designer"
        save_state "test-design-rework" "test-designer"
        return 1
    fi

    log "✅ Test review PASSED"
    log "🚀 Starting ci-specialist..."

    save_state "ci-design" "ci-specialist"

    log "📋 Next: ci-specialist will design CI/CD pipeline"
}

# ===================================================================
# メインエントリーポイント
# ===================================================================
main() {
    local hook_name="${1:-}"

    if [ -z "$hook_name" ]; then
        echo "Usage: $0 <hook_name>"
        echo ""
        echo "Available hooks:"
        echo "  on-spec-complete"
        echo "  on-arch-approved"
        echo "  on-implementation-complete"
        echo "  on-code-review-result"
        echo "  on-test-design-complete"
        echo "  on-test-review-result"
        exit 1
    fi

    log "========================================"
    log "Workflow Engine: $hook_name"
    log "========================================"

    case "$hook_name" in
        on-spec-complete)
            on_spec_complete
            ;;
        on-arch-approved)
            on_arch_approved
            ;;
        on-implementation-complete)
            on_implementation_complete
            ;;
        on-code-review-result)
            on_code_review_result
            ;;
        on-test-design-complete)
            on_test_design_complete
            ;;
        on-test-review-result)
            on_test_review_result
            ;;
        *)
            log "❌ Unknown hook: $hook_name"
            exit 1
            ;;
    esac

    log "========================================"
}

main "$@"

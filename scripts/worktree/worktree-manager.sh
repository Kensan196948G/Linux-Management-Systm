#!/bin/bash
# Git WorkTree 管理スクリプト
#
# 1機能 = 1 WorkTree/ブランチ で並列開発を支援

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# カラー出力
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# ログ出力
log_info() {
    echo -e "${GREEN}[INFO]${NC} $*"
}

log_warn() {
    echo -e "${YELLOW}[WARN]${NC} $*"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $*"
}

# 使用方法
usage() {
    cat << EOF
Git WorkTree Manager - 並列開発支援ツール

使用方法:
  $0 <command> [options]

コマンド:
  create <feature-name>     新しい WorkTree を作成
  list                      WorkTree 一覧を表示
  switch <feature-name>     WorkTree に切り替え
  remove <feature-name>     WorkTree を削除
  cleanup                   削除された WorkTree をクリーンアップ
  status                    全 WorkTree の状態を表示

例:
  # 新機能用 WorkTree を作成
  $0 create user-management

  # WorkTree 一覧を表示
  $0 list

  # WorkTree を削除
  $0 remove user-management
EOF
    exit 1
}

# ===================================================================
# WorkTree 作成
# ===================================================================
create_worktree() {
    local feature_name="$1"

    if [ -z "$feature_name" ]; then
        log_error "機能名を指定してください"
        usage
    fi

    # ブランチ名の生成
    local branch_name="feature/${feature_name}"

    # WorkTree ディレクトリ
    local worktree_dir="${PROJECT_ROOT}/../${feature_name}-worktree"

    log_info "WorkTree を作成中..."
    log_info "  機能名: $feature_name"
    log_info "  ブランチ: $branch_name"
    log_info "  ディレクトリ: $worktree_dir"

    # ブランチが既に存在するかチェック
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        log_warn "ブランチ $branch_name は既に存在します"
        read -p "既存のブランチを使用しますか？ (y/N): " -n 1 -r
        echo
        if [[ ! $REPLY =~ ^[Yy]$ ]]; then
            log_info "キャンセルしました"
            exit 0
        fi
    else
        # 新しいブランチを作成
        log_info "ブランチ $branch_name を作成中..."
        git branch "$branch_name"
    fi

    # WorkTree を作成
    if [ -d "$worktree_dir" ]; then
        log_error "WorkTree ディレクトリが既に存在します: $worktree_dir"
        exit 1
    fi

    git worktree add "$worktree_dir" "$branch_name"

    log_info "✅ WorkTree を作成しました"
    log_info ""
    log_info "次のステップ:"
    log_info "  cd $worktree_dir"
    log_info "  # 開発作業を開始"
    log_info ""
}

# ===================================================================
# WorkTree 一覧表示
# ===================================================================
list_worktrees() {
    log_info "WorkTree 一覧:"
    echo ""

    git worktree list

    echo ""
    log_info "合計: $(git worktree list | wc -l) 個の WorkTree"
}

# ===================================================================
# WorkTree 削除
# ===================================================================
remove_worktree() {
    local feature_name="$1"

    if [ -z "$feature_name" ]; then
        log_error "機能名を指定してください"
        usage
    fi

    local worktree_dir="${PROJECT_ROOT}/../${feature_name}-worktree"

    log_warn "WorkTree を削除します: $worktree_dir"
    read -p "本当に削除しますか？ (y/N): " -n 1 -r
    echo

    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        log_info "キャンセルしました"
        exit 0
    fi

    # WorkTree を削除
    if [ -d "$worktree_dir" ]; then
        git worktree remove "$worktree_dir" --force
        log_info "✅ WorkTree を削除しました"
    else
        log_warn "WorkTree ディレクトリが見つかりません: $worktree_dir"
        log_info "git worktree prune を実行してクリーンアップします..."
        git worktree prune
    fi

    # ブランチも削除するか確認
    local branch_name="feature/${feature_name}"
    if git show-ref --verify --quiet "refs/heads/$branch_name"; then
        read -p "ブランチ $branch_name も削除しますか？ (y/N): " -n 1 -r
        echo
        if [[ $REPLY =~ ^[Yy]$ ]]; then
            git branch -D "$branch_name"
            log_info "✅ ブランチを削除しました: $branch_name"
        fi
    fi
}

# ===================================================================
# WorkTree クリーンアップ
# ===================================================================
cleanup_worktrees() {
    log_info "削除された WorkTree をクリーンアップ中..."

    git worktree prune -v

    log_info "✅ クリーンアップ完了"
}

# ===================================================================
# WorkTree 状態表示
# ===================================================================
status_worktrees() {
    log_info "WorkTree 状態:"
    echo ""

    git worktree list | while read -r line; do
        # WorkTree のパスを抽出
        worktree_path=$(echo "$line" | awk '{print $1}')
        branch=$(echo "$line" | grep -oP '\[\K[^\]]+' || echo "detached")

        echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        echo "📁 $worktree_path"
        echo "🌿 Branch: $branch"

        if [ -d "$worktree_path" ]; then
            cd "$worktree_path"

            # Git 状態
            if [ -n "$(git status --porcelain)" ]; then
                echo -e "${YELLOW}⚠️  未コミットの変更あり${NC}"
                git status --short | head -5
            else
                echo -e "${GREEN}✅ クリーン${NC}"
            fi

            cd - > /dev/null
        fi
    done

    echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ===================================================================
# WorkTree 切り替え
# ===================================================================
switch_worktree() {
    local feature_name="$1"

    if [ -z "$feature_name" ]; then
        log_error "機能名を指定してください"
        usage
    fi

    local worktree_dir="${PROJECT_ROOT}/../${feature_name}-worktree"

    if [ ! -d "$worktree_dir" ]; then
        log_error "WorkTree が見つかりません: $worktree_dir"
        log_info "作成するには: $0 create $feature_name"
        exit 1
    fi

    log_info "WorkTree に切り替え: $worktree_dir"
    log_info "次のコマンドを実行してください:"
    echo ""
    echo "  cd $worktree_dir"
    echo ""
}

# ===================================================================
# メインエントリーポイント
# ===================================================================
main() {
    local command="${1:-}"

    if [ -z "$command" ]; then
        usage
    fi

    # Git リポジトリかチェック
    if ! git rev-parse --git-dir > /dev/null 2>&1; then
        log_error "Git リポジトリではありません"
        exit 1
    fi

    cd "$PROJECT_ROOT"

    case "$command" in
        create)
            shift
            create_worktree "$@"
            ;;
        list)
            list_worktrees
            ;;
        switch)
            shift
            switch_worktree "$@"
            ;;
        remove)
            shift
            remove_worktree "$@"
            ;;
        cleanup)
            cleanup_worktrees
            ;;
        status)
            status_worktrees
            ;;
        *)
            log_error "不明なコマンド: $command"
            usage
            ;;
    esac
}

main "$@"

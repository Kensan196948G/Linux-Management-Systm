#!/bin/bash
# ガードスクリプト - 自動修復の暴走防止
#
# 無限ループ防止、差分量制限、対象ファイル制限

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

echo "========================================="
echo "自動修復ガードチェック"
echo "========================================="
echo ""

# ===================================================================
# 1. 無限ループ防止（試行回数制限）
# ===================================================================
echo "📋 Check 1: 無限ループ防止"
echo "-----------------------------------------"

MAX_ATTEMPTS=5
ATTEMPT_FILE=".ci_attempt_count"

# 試行回数を読み込み
if [ -f "$ATTEMPT_FILE" ]; then
    ATTEMPT=$(cat "$ATTEMPT_FILE")
else
    ATTEMPT=0
fi

ATTEMPT=$((ATTEMPT + 1))
echo "$ATTEMPT" > "$ATTEMPT_FILE"

echo "現在の試行回数: $ATTEMPT / $MAX_ATTEMPTS"

if [ "$ATTEMPT" -gt "$MAX_ATTEMPTS" ]; then
    echo "❌ 最大試行回数を超えました"
    echo "   手動での介入が必要です"
    exit 1
fi

echo "✅ 試行回数: OK"
echo ""

# ===================================================================
# 2. 同一エラー検出
# ===================================================================
echo "📋 Check 2: 同一エラー検出"
echo "-----------------------------------------"

ERROR_HASH_FILE=".ci_error_hash"
BUILD_LOG="${BUILD_LOG:-build.log}"

if [ -f "$BUILD_LOG" ]; then
    # ビルドログのハッシュを計算
    CURRENT_HASH=$(sha1sum "$BUILD_LOG" | awk '{print $1}')

    if [ -f "$ERROR_HASH_FILE" ]; then
        LAST_HASH=$(cat "$ERROR_HASH_FILE")

        if [ "$CURRENT_HASH" = "$LAST_HASH" ]; then
            echo "❌ 同一エラーが繰り返されています"
            echo "   自動修復ループを停止します"
            exit 1
        fi
    fi

    # ハッシュを保存
    echo "$CURRENT_HASH" > "$ERROR_HASH_FILE"

    echo "✅ 同一エラー: なし"
else
    echo "⚠️ ビルドログが見つかりません（スキップ）"
fi

echo ""

# ===================================================================
# 3. 差分量制限
# ===================================================================
echo "📋 Check 3: 差分量制限"
echo "-----------------------------------------"

MAX_DIFF_LINES=20

# 変更行数をカウント
DIFF_LINES=$(git diff | wc -l)

echo "変更行数: $DIFF_LINES / $MAX_DIFF_LINES"

if [ "$DIFF_LINES" -gt "$MAX_DIFF_LINES" ]; then
    echo "❌ 差分が大きすぎます（$DIFF_LINES 行）"
    echo ""
    echo "変更内容:"
    git diff --stat
    echo ""
    echo "大規模な変更は手動でレビューしてください"
    exit 1
fi

echo "✅ 差分量: OK"
echo ""

# ===================================================================
# 4. 対象ファイル制限
# ===================================================================
echo "📋 Check 4: 対象ファイル制限"
echo "-----------------------------------------"

# 変更されたファイルを取得
CHANGED_FILES=$(git diff --name-only)

if [ -z "$CHANGED_FILES" ]; then
    echo "⚠️ 変更ファイルなし"
    exit 0
fi

echo "変更されたファイル:"
echo "$CHANGED_FILES"
echo ""

# 許可されたファイルタイプ
ALLOWED_EXTENSIONS=("\.py$" "\.sh$" "^ci/")

FORBIDDEN_CHANGES=false

while IFS= read -r file; do
    # 空行をスキップ
    [ -z "$file" ] && continue

    # 許可されたファイルかチェック
    FILE_ALLOWED=false

    for ext in "${ALLOWED_EXTENSIONS[@]}"; do
        if [[ "$file" =~ $ext ]]; then
            FILE_ALLOWED=true
            break
        fi
    done

    if [ "$FILE_ALLOWED" = false ]; then
        echo "❌ 許可されていないファイルが変更されています: $file"
        FORBIDDEN_CHANGES=true
    fi
done <<< "$CHANGED_FILES"

if [ "$FORBIDDEN_CHANGES" = true ]; then
    echo ""
    echo "自動修復は .py, .sh, ci/* のみを対象としています"
    exit 1
fi

echo "✅ 対象ファイル: OK"
echo ""

# ===================================================================
# ガードチェック完了
# ===================================================================
echo "========================================="
echo "✅ 全ガードチェック通過"
echo "========================================="
echo ""
echo "自動修復を続行できます:"
echo "  試行回数: $ATTEMPT / $MAX_ATTEMPTS"
echo "  差分量: $DIFF_LINES 行"
echo "  変更ファイル: 許可された範囲内"
echo ""

exit 0

#!/bin/bash
# adminui-processes.sh のテストスクリプト
#
# 用途: ラッパースクリプトの全パターンテスト
# 実行: bash test-adminui-processes.sh

set -euo pipefail

WRAPPER="../adminui-processes.sh"
PASS_COUNT=0
FAIL_COUNT=0

# カラー出力
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# テストヘルパー
pass() {
    echo -e "${GREEN}✅ PASS:${NC} $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo -e "${RED}❌ FAIL:${NC} $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

info() {
    echo -e "${YELLOW}ℹ INFO:${NC} $1"
}

# ===================================================================
# 正常系テスト
# ===================================================================

info "Starting normal case tests..."

# Test 1: デフォルトパラメータ
if OUTPUT=$("$WRAPPER" 2>&1); then
    if echo "$OUTPUT" | jq -e '.status == "success"' > /dev/null 2>/dev/null; then
        pass "Default parameters"
    else
        fail "Default parameters: status not success"
        echo "$OUTPUT"
    fi
else
    fail "Default parameters: execution failed"
fi

# Test 2: ソート指定（cpu）
if OUTPUT=$("$WRAPPER" --sort=cpu --limit=10 2>&1); then
    if echo "$OUTPUT" | jq -e '.sort_by == "cpu"' > /dev/null 2>/dev/null; then
        pass "Sort by cpu"
    else
        fail "Sort by cpu: incorrect sort_by"
    fi
else
    fail "Sort by cpu: execution failed"
fi

# Test 3: ソート指定（mem）
if OUTPUT=$("$WRAPPER" --sort=mem --limit=10 2>&1); then
    if echo "$OUTPUT" | jq -e '.sort_by == "mem"' > /dev/null 2>/dev/null; then
        pass "Sort by mem"
    else
        fail "Sort by mem: incorrect sort_by"
    fi
else
    fail "Sort by mem: execution failed"
fi

# Test 4: ソート指定（pid）
if OUTPUT=$("$WRAPPER" --sort=pid --limit=10 2>&1); then
    if echo "$OUTPUT" | jq -e '.sort_by == "pid"' > /dev/null 2>/dev/null; then
        pass "Sort by pid"
    else
        fail "Sort by pid: incorrect sort_by"
    fi
else
    fail "Sort by pid: execution failed"
fi

# Test 5: ソート指定（time）
if OUTPUT=$("$WRAPPER" --sort=time --limit=10 2>&1); then
    if echo "$OUTPUT" | jq -e '.sort_by == "time"' > /dev/null 2>/dev/null; then
        pass "Sort by time"
    else
        fail "Sort by time: incorrect sort_by"
    fi
else
    fail "Sort by time: execution failed"
fi

# Test 6: ユーザーフィルタ（root）
if OUTPUT=$("$WRAPPER" --filter-user=root 2>&1); then
    if echo "$OUTPUT" | jq -e '.filters.user == "root"' > /dev/null 2>/dev/null; then
        pass "Filter by root user"
    else
        fail "Filter by root user: incorrect filter"
    fi
else
    fail "Filter by root user: execution failed"
fi

# Test 7: limit 指定
if OUTPUT=$("$WRAPPER" --limit=5 2>&1); then
    if echo "$OUTPUT" | jq -e '.returned_processes <= 5' > /dev/null 2>/dev/null; then
        pass "Limit to 5 processes"
    else
        fail "Limit to 5 processes: limit not respected"
    fi
else
    fail "Limit to 5 processes: execution failed"
fi

# Test 8: CPU フィルタ
if OUTPUT=$("$WRAPPER" --min-cpu=0.0 2>&1); then
    if echo "$OUTPUT" | jq -e '.filters.min_cpu == 0.0' > /dev/null 2>/dev/null; then
        pass "Min CPU filter"
    else
        fail "Min CPU filter: incorrect filter"
    fi
else
    fail "Min CPU filter: execution failed"
fi

# Test 9: メモリフィルタ
if OUTPUT=$("$WRAPPER" --min-mem=0.0 2>&1); then
    if echo "$OUTPUT" | jq -e '.filters.min_mem == 0.0' > /dev/null 2>/dev/null; then
        pass "Min memory filter"
    else
        fail "Min memory filter: incorrect filter"
    fi
else
    fail "Min memory filter: execution failed"
fi

# ===================================================================
# 異常系テスト
# ===================================================================

info "Starting abnormal case tests..."

# Test 10: 不正なソートキー
OUTPUT=$("$WRAPPER" --sort=invalid 2>&1) && EXITCODE=$? || EXITCODE=$?
if [ $EXITCODE -ne 0 ]; then
    if echo "$OUTPUT" | grep -qi "Invalid sort key"; then
        pass "Reject invalid sort key"
    else
        fail "Reject invalid sort key: wrong error message"
        echo "$OUTPUT" | head -3
    fi
else
    fail "Should reject invalid sort key (exit code was 0)"
fi

# Test 11: allowlist 外のユーザー
if OUTPUT=$("$WRAPPER" --filter-user=hacker 2>&1); then
    fail "Should reject user not in allowlist"
else
    if echo "$OUTPUT" | grep -qi "not in allowlist"; then
        pass "Reject user not in allowlist"
    else
        fail "Reject user not in allowlist: wrong error message"
    fi
fi

# Test 12: 特殊文字（セミコロン）
if OUTPUT=$("$WRAPPER" --filter-user="root;ls" 2>&1); then
    fail "Should reject forbidden character (semicolon)"
else
    if echo "$OUTPUT" | grep -qi "Forbidden character"; then
        pass "Reject forbidden character (semicolon)"
    else
        fail "Reject forbidden character (semicolon): wrong error message"
    fi
fi

# Test 13: 特殊文字（パイプ）
if OUTPUT=$("$WRAPPER" --filter-user="root|ls" 2>&1); then
    fail "Should reject forbidden character (pipe)"
else
    if echo "$OUTPUT" | grep -qi "Forbidden character"; then
        pass "Reject forbidden character (pipe)"
    else
        fail "Reject forbidden character (pipe): wrong error message"
    fi
fi

# Test 14: 特殊文字（アンパサンド）
if OUTPUT=$("$WRAPPER" --filter-user="root&ls" 2>&1); then
    fail "Should reject forbidden character (ampersand)"
else
    if echo "$OUTPUT" | grep -qi "Forbidden character"; then
        pass "Reject forbidden character (ampersand)"
    else
        fail "Reject forbidden character (ampersand): wrong error message"
    fi
fi

# Test 15: 特殊文字（ドル記号）
if OUTPUT=$("$WRAPPER" --filter-user="root\$ls" 2>&1); then
    fail "Should reject forbidden character (dollar)"
else
    if echo "$OUTPUT" | grep -qi "Forbidden character"; then
        pass "Reject forbidden character (dollar)"
    else
        fail "Reject forbidden character (dollar): wrong error message"
    fi
fi

# Test 16: 特殊文字（バッククォート）
if OUTPUT=$("$WRAPPER" --filter-user='root`ls`' 2>&1); then
    fail "Should reject forbidden character (backtick)"
else
    if echo "$OUTPUT" | grep -qi "Forbidden character"; then
        pass "Reject forbidden character (backtick)"
    else
        fail "Reject forbidden character (backtick): wrong error message"
    fi
fi

# Test 17: 範囲外の limit（最小値未満）
if OUTPUT=$("$WRAPPER" --limit=0 2>&1); then
    fail "Should reject out-of-range limit (0)"
else
    if echo "$OUTPUT" | grep -qi "out of range"; then
        pass "Reject out-of-range limit (0)"
    else
        fail "Reject out-of-range limit (0): wrong error message"
    fi
fi

# Test 18: 範囲外の limit（最大値超過）
if OUTPUT=$("$WRAPPER" --limit=9999 2>&1); then
    fail "Should reject out-of-range limit (9999)"
else
    if echo "$OUTPUT" | grep -qi "out of range"; then
        pass "Reject out-of-range limit (9999)"
    else
        fail "Reject out-of-range limit (9999): wrong error message"
    fi
fi

# Test 19: 不明な引数
if OUTPUT=$("$WRAPPER" --unknown-arg 2>&1); then
    fail "Should reject unknown argument"
else
    if echo "$OUTPUT" | grep -qi "Unknown argument"; then
        pass "Reject unknown argument"
    else
        fail "Reject unknown argument: wrong error message"
    fi
fi

# ===================================================================
# JSON 形式検証
# ===================================================================

info "Starting JSON validation tests..."

# Test 20: JSON 形式の検証
if OUTPUT=$("$WRAPPER" 2>/dev/null); then
    if echo "$OUTPUT" | jq empty > /dev/null 2>&1; then
        pass "Output is valid JSON"
    else
        fail "Output is not valid JSON"
        echo "$OUTPUT"
    fi
else
    fail "JSON validation: execution failed"
fi

# Test 21: 必須フィールドの存在確認
if OUTPUT=$("$WRAPPER" 2>/dev/null); then
    if echo "$OUTPUT" | jq -e '.status and .processes and .timestamp' > /dev/null 2>&1; then
        pass "Required fields exist"
    else
        fail "Required fields missing"
    fi
else
    fail "Required fields check: execution failed"
fi

# ===================================================================
# 結果表示
# ===================================================================

echo ""
echo "=========================================="
echo "Test Results:"
echo -e "  ${GREEN}PASS: $PASS_COUNT${NC}"
echo -e "  ${RED}FAIL: $FAIL_COUNT${NC}"
echo "=========================================="

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo -e "${GREEN}✅ All tests passed!${NC}"
    exit 0
else
    echo -e "${RED}❌ Some tests failed.${NC}"
    exit 1
fi

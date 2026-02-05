#!/bin/bash
# ラッパースクリプトの統合テスト

# 注意: テストでは意図的にエラーを発生させるため、pipefail は無効化
set -eo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WRAPPERS_DIR="$(cd "$SCRIPT_DIR/.." && pwd)"

PASS_COUNT=0
FAIL_COUNT=0

# テスト結果の記録
pass() {
    echo "✅ PASS: $1"
    PASS_COUNT=$((PASS_COUNT + 1))
}

fail() {
    echo "❌ FAIL: $1"
    FAIL_COUNT=$((FAIL_COUNT + 1))
}

echo "========================================="
echo "Wrapper Scripts Test Suite"
echo "========================================="
echo ""

# ===================================================================
# Test 1: adminui-status.sh
# ===================================================================
echo "Test 1: adminui-status.sh"
echo "-----------------------------------------"

# 正常系: 引数なしで実行
if OUTPUT=$(bash "$WRAPPERS_DIR/adminui-status.sh" 2>&1); then
    if echo "$OUTPUT" | grep -q '"cpu"'; then
        pass "adminui-status.sh returns CPU info"
    else
        fail "adminui-status.sh missing CPU info"
    fi

    if echo "$OUTPUT" | grep -q '"memory"'; then
        pass "adminui-status.sh returns memory info"
    else
        fail "adminui-status.sh missing memory info"
    fi
else
    fail "adminui-status.sh execution failed"
fi

echo ""

# ===================================================================
# Test 2: adminui-service-restart.sh
# ===================================================================
echo "Test 2: adminui-service-restart.sh"
echo "-----------------------------------------"

# 正常系: 許可されたサービス（dry-run、実際には実行しない）
# 注意: 実際のテストでは sudo が必要なため、入力検証のみテスト

# 異常系: 引数なし
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "usage\|argument"; then
    pass "Rejects execution without arguments"
else
    fail "Should reject execution without arguments"
fi

# 異常系: 特殊文字（コマンドインジェクション試行）
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" "nginx; rm -rf /" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "forbidden\|invalid"; then
    pass "Rejects command injection attempt (;)"
else
    fail "Should reject command injection"
fi

# 異常系: パイプ
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" "nginx|ls" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "forbidden\|invalid"; then
    pass "Rejects pipe character (|)"
else
    fail "Should reject pipe character"
fi

# 異常系: コマンド置換
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" 'nginx$(whoami)' 2>&1 || true)
if echo "$OUTPUT" | grep -qi "forbidden\|invalid"; then
    pass "Rejects command substitution"
else
    fail "Should reject command substitution"
fi

# 異常系: 許可リスト外のサービス
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" "malicious-service" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not.*allowlist\|not allowed"; then
    pass "Rejects service not in allowlist"
else
    fail "Should reject non-allowlisted service"
fi

# 異常系: 空文字
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-service-restart.sh" "" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "empty\|usage\|argument"; then
    pass "Rejects empty service name"
else
    fail "Should reject empty service name"
fi

echo ""

# ===================================================================
# Test 3: adminui-logs.sh
# ===================================================================
echo "Test 3: adminui-logs.sh"
echo "-----------------------------------------"

# 異常系: 引数なし
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-logs.sh" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "usage\|argument"; then
    pass "Rejects execution without arguments"
else
    fail "Should reject execution without arguments"
fi

# 異常系: 特殊文字
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-logs.sh" "nginx; cat /etc/passwd" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "forbidden\|invalid"; then
    pass "Rejects command injection in logs"
else
    fail "Should reject command injection in logs"
fi

# 異常系: 許可リスト外のサービス
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-logs.sh" "malicious" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "not.*allowlist\|not allowed"; then
    pass "Rejects non-allowlisted service for logs"
else
    fail "Should reject non-allowlisted service for logs"
fi

# 異常系: 不正な行数（文字列）
OUTPUT=$(bash "$WRAPPERS_DIR/adminui-logs.sh" "nginx" "abc" 2>&1 || true)
if echo "$OUTPUT" | grep -qi "invalid.*lines\|must be.*number"; then
    pass "Rejects non-numeric lines parameter"
else
    fail "Should reject non-numeric lines"
fi

# 正常系: 有効な引数（dry-run）
# 注意: 実際のログ取得には sudo が必要

echo ""

# ===================================================================
# Test 4: セキュリティパターン検出
# ===================================================================
echo "Test 4: Security Pattern Detection"
echo "-----------------------------------------"

# shell=True が使用されていないことを確認
if grep -r "shell=True" "$WRAPPERS_DIR"/*.sh; then
    fail "shell=True found in wrapper scripts"
else
    pass "No shell=True usage detected"
fi

# bash -c が使用されていないことを確認
if grep -r "bash -c" "$WRAPPERS_DIR"/*.sh; then
    fail "bash -c found in wrapper scripts"
else
    pass "No bash -c usage detected"
fi

# eval が使用されていないことを確認
if grep -rE "\beval\s+" "$WRAPPERS_DIR"/*.sh; then
    fail "eval command found in wrapper scripts"
else
    pass "No eval usage detected"
fi

echo ""

# ===================================================================
# 結果サマリー
# ===================================================================
echo "========================================="
echo "Test Results Summary"
echo "========================================="
echo "PASSED: $PASS_COUNT"
echo "FAILED: $FAIL_COUNT"
echo ""

if [ "$FAIL_COUNT" -eq 0 ]; then
    echo "✅ All tests passed!"
    exit 0
else
    echo "❌ Some tests failed"
    exit 1
fi

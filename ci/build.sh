#!/bin/bash
# ビルドスクリプト（Bash版）
#
# CI/CD で実行される統合ビルド・テストスクリプト

set -euo pipefail

echo "========================================="
echo "Linux Management System - Build Script"
echo "========================================="
echo ""

# プロジェクトルート
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

cd "$PROJECT_ROOT"

# ===================================================================
# 1. Shell スクリプト構文チェック
# ===================================================================
echo "📋 Step 1: Shell スクリプト構文チェック"
echo "-----------------------------------------"

if command -v shellcheck > /dev/null; then
    echo "ShellCheck でラッパースクリプトを検証中..."

    if find wrappers -name "adminui-*.sh" -type f | xargs shellcheck; then
        echo "✅ ShellCheck: PASS"
    else
        echo "❌ ShellCheck: FAIL"
        exit 1
    fi
else
    echo "⚠️ ShellCheck がインストールされていません（スキップ）"
fi

echo ""

# ===================================================================
# 2. Python 構文チェック・Lint
# ===================================================================
echo "📋 Step 2: Python 構文チェック・Lint"
echo "-----------------------------------------"

if [ -d "venv" ]; then
    source venv/bin/activate
else
    echo "⚠️ Python 仮想環境が見つかりません"
    exit 1
fi

# 構文チェック
echo "Python 構文チェック中..."
if python -m py_compile backend/**/*.py 2>/dev/null; then
    echo "✅ 構文チェック: PASS"
else
    echo "❌ 構文チェック: FAIL"
    exit 1
fi

# flake8
if command -v flake8 > /dev/null; then
    echo "flake8 実行中..."
    if flake8 backend/ --count --select=E9,F63,F7,F82 --show-source --statistics; then
        echo "✅ flake8: PASS"
    else
        echo "❌ flake8: FAIL"
        exit 1
    fi
fi

echo ""

# ===================================================================
# 3. セキュリティスキャン
# ===================================================================
echo "📋 Step 3: セキュリティスキャン（Bandit）"
echo "-----------------------------------------"

if command -v bandit > /dev/null; then
    echo "Bandit セキュリティスキャン中..."

    # HIGH/CRITICAL のみチェック
    if bandit -r backend/ -ll -f json -o bandit-report.json; then
        echo "✅ Bandit: PASS（HIGH/CRITICAL issues なし）"
    else
        echo "❌ Bandit: FAIL（セキュリティ問題を検出）"
        cat bandit-report.json
        exit 1
    fi
else
    echo "⚠️ Bandit がインストールされていません"
fi

echo ""

# ===================================================================
# 4. 禁止パターン検出
# ===================================================================
echo "📋 Step 4: 禁止パターン検出"
echo "-----------------------------------------"

# shell=True 検出
echo "shell=True チェック中..."
if grep -r --include="*.py" "shell=True" backend/ | grep -v "^.*#"; then
    echo "❌ shell=True が検出されました（CRITICAL）"
    exit 1
else
    echo "✅ shell=True: なし"
fi

# os.system 検出
echo "os.system チェック中..."
if grep -rE --include="*.py" "os\.system\s*\(" backend/; then
    echo "❌ os.system が検出されました（CRITICAL）"
    exit 1
else
    echo "✅ os.system: なし"
fi

# eval/exec 検出
echo "eval/exec チェック中..."
if grep -rE --include="*.py" "\b(eval|exec)\s*\(" backend/ | grep -v "^.*#"; then
    echo "❌ eval/exec が検出されました（CRITICAL）"
    exit 1
else
    echo "✅ eval/exec: なし"
fi

echo ""

# ===================================================================
# 5. 単体テスト実行
# ===================================================================
echo "📋 Step 5: 単体テスト実行（pytest）"
echo "-----------------------------------------"

export ENV=dev

if pytest tests/ -v --tb=short --cov=backend --cov-report=term-missing; then
    echo "✅ pytest: PASS"
else
    echo "❌ pytest: FAIL"
    exit 1
fi

echo ""

# ===================================================================
# 6. ラッパースクリプトテスト
# ===================================================================
echo "📋 Step 6: sudo ラッパースクリプトテスト"
echo "-----------------------------------------"

if bash wrappers/test/test-all-wrappers.sh; then
    echo "✅ ラッパーテスト: PASS"
else
    echo "❌ ラッパーテスト: FAIL"
    exit 1
fi

echo ""

# ===================================================================
# ビルド成功
# ===================================================================
echo "========================================="
echo "✅ ビルド成功！"
echo "========================================="
echo ""
echo "全チェック完了:"
echo "  ✅ Shell スクリプト構文チェック"
echo "  ✅ Python 構文チェック・Lint"
echo "  ✅ セキュリティスキャン"
echo "  ✅ 禁止パターン検出"
echo "  ✅ 単体テスト（pytest）"
echo "  ✅ ラッパースクリプトテスト"
echo ""

exit 0

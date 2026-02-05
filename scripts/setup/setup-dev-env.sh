#!/bin/bash
# 開発環境セットアップスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "========================================="
echo "開発環境セットアップ"
echo "========================================="
echo ""

# .env ファイルの読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
    echo "✅ .env ファイルを読み込みました"
else
    echo "❌ .env ファイルが見つかりません"
    echo "   .env.example をコピーして .env を作成してください"
    exit 1
fi

# 必要なディレクトリの作成
echo ""
echo "📁 ディレクトリを作成中..."
mkdir -p "$PROJECT_ROOT/data/dev"
mkdir -p "$PROJECT_ROOT/logs/dev"
mkdir -p "$PROJECT_ROOT/certs/dev"
mkdir -p "$PROJECT_ROOT/frontend/dev"
echo "✅ ディレクトリを作成しました"

# SSL 証明書の生成
echo ""
echo "🔐 SSL証明書を生成中..."
bash "$SCRIPT_DIR/generate-ssl-cert.sh" dev
echo "✅ SSL証明書を生成しました"

# Python 仮想環境の確認
echo ""
if [ ! -d "$PROJECT_ROOT/venv" ]; then
    echo "🐍 Python 仮想環境を作成中..."
    python3 -m venv "$PROJECT_ROOT/venv"
    echo "✅ Python 仮想環境を作成しました"
else
    echo "ℹ️ Python 仮想環境は既に存在します"
fi

# 依存関係のインストール（backend が存在する場合）
if [ -f "$PROJECT_ROOT/backend/requirements.txt" ]; then
    echo ""
    echo "📦 依存関係をインストール中..."
    source "$PROJECT_ROOT/venv/bin/activate"
    pip install -r "$PROJECT_ROOT/backend/requirements.txt"
    echo "✅ 依存関係をインストールしました"
fi

# Node.js 依存関係のインストール（frontend が存在する場合）
if [ -f "$PROJECT_ROOT/frontend/package.json" ]; then
    echo ""
    echo "📦 Node.js 依存関係をインストール中..."
    cd "$PROJECT_ROOT/frontend"
    npm install
    cd "$PROJECT_ROOT"
    echo "✅ Node.js 依存関係をインストールしました"
fi

# ポート番号の衝突チェック
echo ""
echo "🔍 ポート番号の衝突をチェック中..."
if netstat -tuln 2>/dev/null | grep -q ":$DEV_PORT "; then
    echo "⚠️ 警告: ポート $DEV_PORT は既に使用されています"
else
    echo "✅ ポート $DEV_PORT は使用可能です"
fi

if netstat -tuln 2>/dev/null | grep -q ":$DEV_HTTPS_PORT "; then
    echo "⚠️ 警告: ポート $DEV_HTTPS_PORT は既に使用されています"
else
    echo "✅ ポート $DEV_HTTPS_PORT は使用可能です"
fi

# 設定ファイルの確認
echo ""
echo "📋 設定ファイルを確認中..."
if [ -f "$PROJECT_ROOT/config/dev.json" ]; then
    echo "✅ config/dev.json が存在します"
else
    echo "⚠️ config/dev.json が見つかりません"
fi

echo ""
echo "========================================="
echo "✅ 開発環境のセットアップが完了しました"
echo "========================================="
echo ""
echo "次のステップ:"
echo "  1. 開発サーバーを起動:"
echo "     cd backend"
echo "     source ../venv/bin/activate"
echo "     uvicorn api.main:app --host $DEV_IP --port $DEV_PORT --reload"
echo ""
echo "  2. HTTPS で起動する場合:"
echo "     uvicorn api.main:app --host $DEV_IP --port $DEV_HTTPS_PORT --ssl-keyfile ./certs/dev/key.pem --ssl-certfile ./certs/dev/cert.pem"
echo ""
echo "  3. アクセスURL:"
echo "     HTTP:  http://localhost:$DEV_PORT"
echo "     HTTPS: https://localhost:$DEV_HTTPS_PORT"
echo ""

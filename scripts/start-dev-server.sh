#!/bin/bash
# 開発サーバー起動スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

echo "========================================="
echo "開発サーバー起動"
echo "========================================="
echo ""

# .env ファイルの読み込み
if [ -f "$PROJECT_ROOT/.env" ]; then
    source "$PROJECT_ROOT/.env"
    echo "✅ .env ファイルを読み込みました"
else
    echo "❌ .env ファイルが見つかりません"
    exit 1
fi

# 環境変数を設定
export ENV=dev

# Python 仮想環境の確認
if [ ! -d "$PROJECT_ROOT/venv" ]; then
    echo "⚠️ Python 仮想環境が見つかりません"
    echo "   セットアップスクリプトを実行してください:"
    echo "   ./scripts/setup/setup-dev-env.sh"
    exit 1
fi

# 仮想環境の有効化
source "$PROJECT_ROOT/venv/bin/activate"

# バックエンドディレクトリに移動
cd "$PROJECT_ROOT"

echo ""
echo "🚀 開発サーバーを起動中..."
echo "   環境: 開発（dev）"
echo "   ポート: $DEV_PORT (HTTP), $DEV_HTTPS_PORT (HTTPS)"
echo ""
echo "アクセスURL:"
echo "   HTTP:  http://localhost:$DEV_PORT"
echo "   HTTPS: https://localhost:$DEV_HTTPS_PORT"
echo "   API ドキュメント: http://localhost:$DEV_PORT/api/docs"
echo ""
echo "停止するには Ctrl+C を押してください"
echo ""

# uvicorn で起動（ホットリロード有効）
uvicorn backend.api.main:app \
    --host "$DEV_IP" \
    --port "$DEV_PORT" \
    --reload \
    --log-level debug

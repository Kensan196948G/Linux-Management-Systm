#!/bin/bash
# 本番環境セットアップスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

echo "========================================="
echo "本番環境セットアップ"
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

# 本番環境用ディレクトリの作成（要 sudo）
echo ""
echo "📁 本番環境用ディレクトリを作成中..."
sudo mkdir -p /var/lib/linux-management
sudo mkdir -p /var/log/linux-management
sudo chown $USER:$USER /var/lib/linux-management
sudo chown $USER:$USER /var/log/linux-management
echo "✅ 本番環境用ディレクトリを作成しました"

# プロジェクト内のディレクトリも作成
mkdir -p "$PROJECT_ROOT/certs/prod"
mkdir -p "$PROJECT_ROOT/frontend/prod"

# SSL 証明書の生成
echo ""
echo "🔐 SSL証明書を生成中..."
bash "$SCRIPT_DIR/generate-ssl-cert.sh" prod
echo "✅ SSL証明書を生成しました"

# Python 仮想環境の確認
echo ""
if [ ! -d "$PROJECT_ROOT/venv-prod" ]; then
    echo "🐍 本番用 Python 仮想環境を作成中..."
    python3 -m venv "$PROJECT_ROOT/venv-prod"
    echo "✅ 本番用 Python 仮想環境を作成しました"
else
    echo "ℹ️ 本番用 Python 仮想環境は既に存在します"
fi

# 依存関係のインストール（本番用）
if [ -f "$PROJECT_ROOT/backend/requirements.txt" ]; then
    echo ""
    echo "📦 本番用依存関係をインストール中..."
    source "$PROJECT_ROOT/venv-prod/bin/activate"
    pip install -r "$PROJECT_ROOT/backend/requirements.txt"
    pip install gunicorn  # 本番用 WSGI サーバー
    echo "✅ 本番用依存関係をインストールしました"
fi

# ポート番号の衝突チェック
echo ""
echo "🔍 ポート番号の衝突をチェック中..."
if netstat -tuln 2>/dev/null | grep -q ":$PROD_PORT "; then
    echo "⚠️ 警告: ポート $PROD_PORT は既に使用されています"
else
    echo "✅ ポート $PROD_PORT は使用可能です"
fi

if netstat -tuln 2>/dev/null | grep -q ":$PROD_HTTPS_PORT "; then
    echo "⚠️ 警告: ポート $PROD_HTTPS_PORT は既に使用されています"
else
    echo "✅ ポート $PROD_HTTPS_PORT は使用可能です"
fi

# 設定ファイルの確認
echo ""
echo "📋 設定ファイルを確認中..."
if [ -f "$PROJECT_ROOT/config/prod.json" ]; then
    echo "✅ config/prod.json が存在します"
else
    echo "⚠️ config/prod.json が見つかりません"
fi

# systemd サービスファイルの確認
echo ""
echo "🔧 systemd サービスの準備..."
if [ -f "$PROJECT_ROOT/systemd/linux-management-prod.service" ]; then
    echo "ℹ️ systemd サービスファイルが存在します"
    echo "   インストールするには:"
    echo "   sudo cp systemd/linux-management-prod.service /etc/systemd/system/"
    echo "   sudo systemctl daemon-reload"
    echo "   sudo systemctl enable linux-management-prod"
    echo "   sudo systemctl start linux-management-prod"
else
    echo "⚠️ systemd サービスファイルがまだ作成されていません"
fi

echo ""
echo "========================================="
echo "✅ 本番環境のセットアップが完了しました"
echo "========================================="
echo ""
echo "⚠️ 本番環境デプロイ前のチェックリスト:"
echo "  [ ] SESSION_SECRET を変更済み（.env）"
echo "  [ ] セキュリティ設定を確認（config/prod.json）"
echo "  [ ] SSL証明書が正しく生成されている"
echo "  [ ] ファイアウォール設定（ポート $PROD_PORT, $PROD_HTTPS_PORT）"
echo "  [ ] sudo ラッパースクリプトの配置（/usr/local/sbin/）"
echo "  [ ] sudoers 設定"
echo ""
echo "本番サーバー起動方法:"
echo "  source venv-prod/bin/activate"
echo "  gunicorn -w 4 -k uvicorn.workers.UvicornWorker \\"
echo "    --bind $PROD_IP:$PROD_HTTPS_PORT \\"
echo "    --keyfile ./certs/prod/key.pem \\"
echo "    --certfile ./certs/prod/cert.pem \\"
echo "    backend.api.main:app"
echo ""

#!/bin/bash
# systemd サービスインストールスクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/.." && pwd)"

# 使用方法
usage() {
    echo "Usage: $0 <dev|prod>"
    echo ""
    echo "Arguments:"
    echo "  dev   - Install development service"
    echo "  prod  - Install production service"
    exit 1
}

if [ $# -ne 1 ]; then
    usage
fi

ENV="$1"

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    usage
fi

echo "========================================="
echo "systemd サービスインストール: $ENV 環境"
echo "========================================="
echo ""

SERVICE_NAME="linux-management-$ENV"
SERVICE_FILE="$PROJECT_ROOT/systemd/$SERVICE_NAME.service"

# サービスファイルの存在確認
if [ ! -f "$SERVICE_FILE" ]; then
    echo "❌ エラー: サービスファイルが見つかりません: $SERVICE_FILE"
    exit 1
fi

echo "サービスファイル: $SERVICE_FILE"
echo ""

# 本番環境の場合は追加確認
if [ "$ENV" = "prod" ]; then
    echo "⚠️ 本番環境サービスをインストールします"
    echo ""
    echo "事前チェックリスト:"
    echo "  [ ] svc-adminui ユーザーが作成されている"
    echo "  [ ] プロジェクトが /opt/linux-management に配置されている"
    echo "  [ ] venv-prod が作成されている"
    echo "  [ ] .env ファイルが配置されている"
    echo "  [ ] sudo ラッパーが /usr/local/sbin/ に配置されている"
    echo "  [ ] sudoers が設定されている"
    echo ""
    read -p "全て完了していますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "キャンセルしました"
        exit 0
    fi
fi

# サービスファイルをコピー
echo "📋 サービスファイルをコピー中..."
sudo cp "$SERVICE_FILE" "/etc/systemd/system/$SERVICE_NAME.service"
echo "✅ サービスファイルをコピーしました"

# systemd リロード
echo ""
echo "🔄 systemd をリロード中..."
sudo systemctl daemon-reload
echo "✅ systemd をリロードしました"

# サービスの有効化
echo ""
echo "✅ サービスを有効化中..."
sudo systemctl enable "$SERVICE_NAME.service"
echo "✅ サービスを有効化しました（機器再起動後に自動起動）"

# サービスの状態確認
echo ""
echo "📊 サービス状態:"
sudo systemctl status "$SERVICE_NAME.service" --no-pager || true

echo ""
echo "========================================="
echo "✅ インストール完了"
echo "========================================="
echo ""
echo "サービス管理コマンド:"
echo "  起動:   sudo systemctl start $SERVICE_NAME"
echo "  停止:   sudo systemctl stop $SERVICE_NAME"
echo "  再起動: sudo systemctl restart $SERVICE_NAME"
echo "  状態:   sudo systemctl status $SERVICE_NAME"
echo "  ログ:   sudo journalctl -u $SERVICE_NAME -f"
echo ""
echo "自動起動設定:"
echo "  有効化: sudo systemctl enable $SERVICE_NAME"
echo "  無効化: sudo systemctl disable $SERVICE_NAME"
echo ""

if [ "$ENV" = "dev" ]; then
    echo "開発サーバーを起動しますか？ (y/N)"
    read -p "> " -n 1 -r
    echo
    if [[ $REPLY =~ ^[Yy]$ ]]; then
        sudo systemctl start "$SERVICE_NAME"
        echo ""
        echo "✅ 開発サーバーを起動しました"
        echo "   アクセス: http://localhost:5012/dev/"
        echo ""
        echo "ログを確認:"
        echo "   sudo journalctl -u $SERVICE_NAME -f"
    fi
fi

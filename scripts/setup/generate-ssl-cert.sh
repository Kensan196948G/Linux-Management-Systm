#!/bin/bash
# SSL 自己署名証明書生成スクリプト

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_ROOT="$(cd "$SCRIPT_DIR/../.." && pwd)"

# 環境パラメータ
ENV="${1:-dev}"

if [[ "$ENV" != "dev" && "$ENV" != "prod" ]]; then
    echo "Usage: $0 <dev|prod>"
    exit 1
fi

CERT_DIR="$PROJECT_ROOT/certs/$ENV"
mkdir -p "$CERT_DIR"

echo "=================================="
echo "SSL 自己署名証明書生成: $ENV 環境"
echo "=================================="

# 証明書情報
COUNTRY="JP"
STATE="Tokyo"
CITY="Tokyo"
ORG="Linux Management System"
ORG_UNIT="IT Department"
COMMON_NAME="localhost"
EMAIL="admin@example.com"

# 証明書の有効期限（日数）
VALID_DAYS=3650  # 10年

echo "証明書ディレクトリ: $CERT_DIR"
echo "有効期限: $VALID_DAYS 日"
echo ""

# 既存の証明書チェック
if [ -f "$CERT_DIR/cert.pem" ] && [ -f "$CERT_DIR/key.pem" ]; then
    read -p "既存の証明書が存在します。上書きしますか？ (y/N): " -n 1 -r
    echo
    if [[ ! $REPLY =~ ^[Yy]$ ]]; then
        echo "キャンセルしました。"
        exit 0
    fi
fi

# OpenSSL で自己署名証明書を生成
echo "🔐 証明書を生成中..."

openssl req -x509 -new node -newkey rsa:4096 -keyout "$CERT_DIR/key.pem" -out "$CERT_DIR/cert.pem" \
    -days "$VALID_DAYS" \
    -subj "/C=$COUNTRY/ST=$STATE/L=$CITY/O=$ORG/OU=$ORG_UNIT/CN=$COMMON_NAME/emailAddress=$EMAIL" \
    -addext "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:0.0.0.0"

# パーミッション設定
chmod 600 "$CERT_DIR/key.pem"
chmod 644 "$CERT_DIR/cert.pem"

echo "✅ 証明書を生成しました"
echo ""
echo "証明書ファイル:"
echo "  証明書: $CERT_DIR/cert.pem"
echo "  秘密鍵: $CERT_DIR/key.pem"
echo ""

# 証明書情報の表示
echo "証明書情報:"
openssl x509 -in "$CERT_DIR/cert.pem" -text -noout | grep -E "(Subject:|Issuer:|Not Before|Not After|DNS:|IP Address:)"

echo ""
echo "=================================="
echo "✅ 完了"
echo "=================================="

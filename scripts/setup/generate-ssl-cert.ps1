# SSL 自己署名証明書生成スクリプト (PowerShell)

param(
    [Parameter(Mandatory=$false)]
    [ValidateSet("dev", "prod")]
    [string]$Environment = "dev"
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)
$CertDir = Join-Path $ProjectRoot "certs\$Environment"

if (-not (Test-Path $CertDir)) {
    New-Item -ItemType Directory -Path $CertDir -Force | Out-Null
}

Write-Host "==================================" -ForegroundColor Cyan
Write-Host "SSL 自己署名証明書生成: $Environment 環境" -ForegroundColor Cyan
Write-Host "==================================" -ForegroundColor Cyan
Write-Host ""

# 証明書情報
$CertSubject = "CN=localhost, O=Linux Management System, OU=IT Department, L=Tokyo, S=Tokyo, C=JP"
$ValidDays = 3650  # 10年

Write-Host "証明書ディレクトリ: $CertDir"
Write-Host "有効期限: $ValidDays 日"
Write-Host ""

# 既存の証明書チェック
$CertPath = Join-Path $CertDir "cert.pem"
$KeyPath = Join-Path $CertDir "key.pem"

if ((Test-Path $CertPath) -and (Test-Path $KeyPath)) {
    $response = Read-Host "既存の証明書が存在します。上書きしますか？ (y/N)"
    if ($response -ne "y" -and $response -ne "Y") {
        Write-Host "キャンセルしました。"
        exit 0
    }
}

# OpenSSL チェック（Windows の場合）
try {
    $null = Get-Command openssl -ErrorAction Stop
} catch {
    Write-Host "❌ OpenSSL が見つかりません。" -ForegroundColor Red
    Write-Host "   OpenSSL をインストールするか、PowerShell の New-SelfSignedCertificate を使用してください。"
    Write-Host ""
    Write-Host "代替方法: PowerShell ネイティブで証明書を生成しています..." -ForegroundColor Yellow

    # PowerShell ネイティブで証明書生成
    $cert = New-SelfSignedCertificate `
        -Subject $CertSubject `
        -DnsName "localhost", "*.localhost" `
        -KeyAlgorithm RSA `
        -KeyLength 4096 `
        -NotAfter (Get-Date).AddDays($ValidDays) `
        -CertStoreLocation "Cert:\CurrentUser\My" `
        -KeyExportPolicy Exportable

    # PEM 形式でエクスポート
    $certBytes = $cert.Export([System.Security.Cryptography.X509Certificates.X509ContentType]::Cert)
    $certPem = "-----BEGIN CERTIFICATE-----`n"
    $certPem += [System.Convert]::ToBase64String($certBytes, [System.Base64FormattingOptions]::InsertLineBreaks)
    $certPem += "`n-----END CERTIFICATE-----"
    Set-Content -Path $CertPath -Value $certPem

    Write-Host "✅ PowerShell ネイティブで証明書を生成しました" -ForegroundColor Green
    Write-Host ""
    Write-Host "証明書ファイル:"
    Write-Host "  証明書: $CertPath"
    Write-Host ""
    Write-Host "⚠️ 注意: PowerShell 生成の証明書は秘密鍵のエクスポートに制限があります。"
    Write-Host "   本番環境では OpenSSL の使用を推奨します。"

    exit 0
}

# OpenSSL で生成
Write-Host "🔐 OpenSSL で証明書を生成中..." -ForegroundColor Cyan

$opensslCmd = @"
openssl req -x509 -newkey rsa:4096 -keyout "$KeyPath" -out "$CertPath" ``
    -days $ValidDays ``
    -nodes ``
    -subj "/C=JP/ST=Tokyo/L=Tokyo/O=Linux Management System/OU=IT Department/CN=localhost" ``
    -addext "subjectAltName=DNS:localhost,DNS:*.localhost,IP:127.0.0.1,IP:0.0.0.0"
"@

Invoke-Expression $opensslCmd

if ($LASTEXITCODE -eq 0) {
    Write-Host "✅ 証明書を生成しました" -ForegroundColor Green
    Write-Host ""
    Write-Host "証明書ファイル:"
    Write-Host "  証明書: $CertPath"
    Write-Host "  秘密鍵: $KeyPath"
    Write-Host ""
    Write-Host "=================================="
    Write-Host "✅ 完了" -ForegroundColor Green
    Write-Host "=================================="
} else {
    Write-Host "❌ 証明書の生成に失敗しました" -ForegroundColor Red
    exit 1
}

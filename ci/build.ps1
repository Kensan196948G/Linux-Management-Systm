# ビルドスクリプト（PowerShell版）
#
# CI/CD で実行される統合ビルド・テストスクリプト

$ErrorActionPreference = "Stop"

Write-Host "=========================================" -ForegroundColor Cyan
Write-Host "Linux Management System - Build Script" -ForegroundColor Cyan
Write-Host "=========================================" -ForegroundColor Cyan
Write-Host ""

$ProjectRoot = Split-Path -Parent $PSScriptRoot
Set-Location $ProjectRoot

# ===================================================================
# 1. PowerShell スクリプト構文チェック
# ===================================================================
Write-Host "📋 Step 1: PowerShell スクリプト構文チェック" -ForegroundColor Yellow
Write-Host "-----------------------------------------"

$psScripts = Get-ChildItem -Path . -Recurse -Filter *.ps1 -Exclude "venv*","node_modules"

if ($psScripts.Count -gt 0) {
    Write-Host "PSScriptAnalyzer で構文チェック中..."

    $hasErrors = $false
    foreach ($script in $psScripts) {
        Write-Host "  チェック中: $($script.Name)"

        # PSScriptAnalyzer がインストールされているかチェック
        if (Get-Command Invoke-ScriptAnalyzer -ErrorAction SilentlyContinue) {
            $results = Invoke-ScriptAnalyzer -Path $script.FullName -Severity Error

            if ($results) {
                Write-Host "  ❌ エラー: $($script.Name)" -ForegroundColor Red
                $results | Format-Table -AutoSize
                $hasErrors = $true
            } else {
                Write-Host "  ✅ OK: $($script.Name)" -ForegroundColor Green
            }
        } else {
            # PSScriptAnalyzer がない場合は構文チェックのみ
            $syntaxErrors = $null
            [void][System.Management.Automation.Language.Parser]::ParseFile(
                $script.FullName, [ref]$null, [ref]$syntaxErrors
            )

            if ($syntaxErrors) {
                Write-Host "  ❌ 構文エラー: $($script.Name)" -ForegroundColor Red
                $hasErrors = $true
            } else {
                Write-Host "  ✅ OK: $($script.Name)" -ForegroundColor Green
            }
        }
    }

    if ($hasErrors) {
        Write-Host "❌ PowerShell スクリプトチェック: FAIL" -ForegroundColor Red
        exit 1
    }

    Write-Host "✅ PowerShell スクリプトチェック: PASS" -ForegroundColor Green
}

Write-Host ""

# ===================================================================
# 2. Python 構文チェック・Lint
# ===================================================================
Write-Host "📋 Step 2: Python 構文チェック・Lint" -ForegroundColor Yellow
Write-Host "-----------------------------------------"

# Python 仮想環境の確認
$venvPath = Join-Path $ProjectRoot "venv"

if (Test-Path $venvPath) {
    # Linux/WSL の場合
    if ($IsLinux -or $IsMacOS) {
        & "$venvPath/bin/python" -m py_compile backend/**/*.py
    } else {
        # Windows の場合
        & "$venvPath\Scripts\python.exe" -m py_compile backend/**/*.py
    }

    Write-Host "✅ Python 構文チェック: PASS" -ForegroundColor Green
} else {
    Write-Host "⚠️ Python 仮想環境が見つかりません" -ForegroundColor Yellow
}

Write-Host ""

# ===================================================================
# 3. セキュリティスキャン
# ===================================================================
Write-Host "📋 Step 3: セキュリティスキャン" -ForegroundColor Yellow
Write-Host "-----------------------------------------"

# shell=True 検出
Write-Host "shell=True チェック中..."
$shellTrue = Select-String -Path backend/**/*.py -Pattern "shell=True" | Where-Object { $_.Line -notmatch "^\s*#" }

if ($shellTrue) {
    Write-Host "❌ shell=True が検出されました（CRITICAL）" -ForegroundColor Red
    $shellTrue | Format-Table -AutoSize
    exit 1
} else {
    Write-Host "✅ shell=True: なし" -ForegroundColor Green
}

Write-Host ""

# ===================================================================
# 4. テスト実行
# ===================================================================
Write-Host "📋 Step 4: テスト実行" -ForegroundColor Yellow
Write-Host "-----------------------------------------"

if (Test-Path $venvPath) {
    $env:ENV = "dev"

    # pytest 実行
    if ($IsLinux -or $IsMacOS) {
        & "$venvPath/bin/pytest" tests/ -v --tb=short
    } else {
        & "$venvPath\Scripts\pytest.exe" tests/ -v --tb=short
    }

    if ($LASTEXITCODE -eq 0) {
        Write-Host "✅ pytest: PASS" -ForegroundColor Green
    } else {
        Write-Host "❌ pytest: FAIL" -ForegroundColor Red
        exit 1
    }
}

Write-Host ""

# ===================================================================
# ビルド成功
# ===================================================================
Write-Host "=========================================" -ForegroundColor Green
Write-Host "✅ ビルド成功！" -ForegroundColor Green
Write-Host "=========================================" -ForegroundColor Green
Write-Host ""

exit 0

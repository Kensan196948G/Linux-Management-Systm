# Git WorkTree 管理スクリプト (PowerShell)
#
# 1機能 = 1 WorkTree/ブランチ で並列開発を支援

param(
    [Parameter(Mandatory=$true, Position=0)]
    [ValidateSet("create", "list", "switch", "remove", "cleanup", "status")]
    [string]$Command,

    [Parameter(Mandatory=$false, Position=1)]
    [string]$FeatureName
)

$ErrorActionPreference = "Stop"

$ProjectRoot = Split-Path -Parent (Split-Path -Parent $PSScriptRoot)

# ログ出力
function Write-Info {
    param([string]$Message)
    Write-Host "[INFO] $Message" -ForegroundColor Green
}

function Write-Warn {
    param([string]$Message)
    Write-Host "[WARN] $Message" -ForegroundColor Yellow
}

function Write-Error {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
}

# ===================================================================
# WorkTree 作成
# ===================================================================
function New-WorkTree {
    param([string]$FeatureName)

    if ([string]::IsNullOrEmpty($FeatureName)) {
        Write-Error "機能名を指定してください"
        Show-Usage
        exit 1
    }

    $BranchName = "feature/$FeatureName"
    $WorkTreeDir = Join-Path (Split-Path -Parent $ProjectRoot) "$FeatureName-worktree"

    Write-Info "WorkTree を作成中..."
    Write-Info "  機能名: $FeatureName"
    Write-Info "  ブランチ: $BranchName"
    Write-Info "  ディレクトリ: $WorkTreeDir"

    # ブランチが既に存在するかチェック
    $branchExists = git show-ref --verify --quiet "refs/heads/$BranchName"
    if ($LASTEXITCODE -eq 0) {
        Write-Warn "ブランチ $BranchName は既に存在します"
        $response = Read-Host "既存のブランチを使用しますか？ (y/N)"
        if ($response -ne "y" -and $response -ne "Y") {
            Write-Info "キャンセルしました"
            exit 0
        }
    } else {
        # 新しいブランチを作成
        Write-Info "ブランチ $BranchName を作成中..."
        git branch $BranchName
    }

    # WorkTree を作成
    if (Test-Path $WorkTreeDir) {
        Write-Error "WorkTree ディレクトリが既に存在します: $WorkTreeDir"
        exit 1
    }

    git worktree add $WorkTreeDir $BranchName

    Write-Info "✅ WorkTree を作成しました"
    Write-Host ""
    Write-Info "次のステップ:"
    Write-Host "  cd $WorkTreeDir"
    Write-Host "  # 開発作業を開始"
    Write-Host ""
}

# ===================================================================
# WorkTree 一覧表示
# ===================================================================
function Get-WorkTrees {
    Write-Info "WorkTree 一覧:"
    Write-Host ""

    git worktree list

    $count = (git worktree list | Measure-Object).Count
    Write-Host ""
    Write-Info "合計: $count 個の WorkTree"
}

# ===================================================================
# WorkTree 削除
# ===================================================================
function Remove-WorkTree {
    param([string]$FeatureName)

    if ([string]::IsNullOrEmpty($FeatureName)) {
        Write-Error "機能名を指定してください"
        Show-Usage
        exit 1
    }

    $WorkTreeDir = Join-Path (Split-Path -Parent $ProjectRoot) "$FeatureName-worktree"

    Write-Warn "WorkTree を削除します: $WorkTreeDir"
    $response = Read-Host "本当に削除しますか？ (y/N)"

    if ($response -ne "y" -and $response -ne "Y") {
        Write-Info "キャンセルしました"
        exit 0
    }

    # WorkTree を削除
    if (Test-Path $WorkTreeDir) {
        git worktree remove $WorkTreeDir --force
        Write-Info "✅ WorkTree を削除しました"
    } else {
        Write-Warn "WorkTree ディレクトリが見つかりません: $WorkTreeDir"
        Write-Info "git worktree prune を実行してクリーンアップします..."
        git worktree prune
    }

    # ブランチも削除するか確認
    $BranchName = "feature/$FeatureName"
    $branchExists = git show-ref --verify --quiet "refs/heads/$BranchName"
    if ($LASTEXITCODE -eq 0) {
        $response = Read-Host "ブランチ $BranchName も削除しますか？ (y/N)"
        if ($response -eq "y" -or $response -eq "Y") {
            git branch -D $BranchName
            Write-Info "✅ ブランチを削除しました: $BranchName"
        }
    }
}

# ===================================================================
# WorkTree クリーンアップ
# ===================================================================
function Invoke-Cleanup {
    Write-Info "削除された WorkTree をクリーンアップ中..."

    git worktree prune -v

    Write-Info "✅ クリーンアップ完了"
}

# ===================================================================
# WorkTree 状態表示
# ===================================================================
function Show-Status {
    Write-Info "WorkTree 状態:"
    Write-Host ""

    $worktrees = git worktree list

    foreach ($line in $worktrees) {
        $parts = $line -split '\s+'
        $path = $parts[0]
        $branch = $line -match '\[([^\]]+)\]' | Out-Null; $matches[1]

        Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
        Write-Host "📁 $path"
        Write-Host "🌿 Branch: $branch"

        if (Test-Path $path) {
            Push-Location $path

            $status = git status --porcelain
            if ($status) {
                Write-Host "⚠️  未コミットの変更あり" -ForegroundColor Yellow
                git status --short | Select-Object -First 5
            } else {
                Write-Host "✅ クリーン" -ForegroundColor Green
            }

            Pop-Location
        }
    }

    Write-Host "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
}

# ===================================================================
# WorkTree 切り替え
# ===================================================================
function Switch-WorkTree {
    param([string]$FeatureName)

    if ([string]::IsNullOrEmpty($FeatureName)) {
        Write-Error "機能名を指定してください"
        Show-Usage
        exit 1
    }

    $WorkTreeDir = Join-Path (Split-Path -Parent $ProjectRoot) "$FeatureName-worktree"

    if (-not (Test-Path $WorkTreeDir)) {
        Write-Error "WorkTree が見つかりません: $WorkTreeDir"
        Write-Info "作成するには: .\worktree-manager.ps1 create $FeatureName"
        exit 1
    }

    Write-Info "WorkTree に切り替え: $WorkTreeDir"
    Write-Info "次のコマンドを実行してください:"
    Write-Host ""
    Write-Host "  cd $WorkTreeDir"
    Write-Host ""
}

# ===================================================================
# 使用方法表示
# ===================================================================
function Show-Usage {
    Write-Host @"
Git WorkTree Manager - 並列開発支援ツール

使用方法:
  .\worktree-manager.ps1 <command> [options]

コマンド:
  create <feature-name>     新しい WorkTree を作成
  list                      WorkTree 一覧を表示
  switch <feature-name>     WorkTree に切り替え
  remove <feature-name>     WorkTree を削除
  cleanup                   削除された WorkTree をクリーンアップ
  status                    全 WorkTree の状態を表示

例:
  # 新機能用 WorkTree を作成
  .\worktree-manager.ps1 create user-management

  # WorkTree 一覧を表示
  .\worktree-manager.ps1 list

  # WorkTree を削除
  .\worktree-manager.ps1 remove user-management
"@
}

# ===================================================================
# メイン処理
# ===================================================================

# Git リポジトリかチェック
try {
    git rev-parse --git-dir | Out-Null
} catch {
    Write-Error "Git リポジトリではありません"
    exit 1
}

Set-Location $ProjectRoot

switch ($Command) {
    "create" {
        New-WorkTree -FeatureName $FeatureName
    }
    "list" {
        Get-WorkTrees
    }
    "switch" {
        Switch-WorkTree -FeatureName $FeatureName
    }
    "remove" {
        Remove-WorkTree -FeatureName $FeatureName
    }
    "cleanup" {
        Invoke-Cleanup
    }
    "status" {
        Show-Status
    }
    default {
        Write-Error "不明なコマンド: $Command"
        Show-Usage
        exit 1
    }
}

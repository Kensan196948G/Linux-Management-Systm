# GitHub Actions Workflows

このディレクトリには、プロジェクトの CI/CD とセキュリティ監査のためのワークフローが含まれています。

---

## 📋 ワークフロー一覧

### 1. CI (`ci.yml`)

**トリガー**: Push（main, develop, feature/*）、Pull Request

**目的**: コードの品質とセキュリティを自動検証

#### Jobs

| Job | 内容 | 失敗条件 |
|-----|------|---------|
| **test** | テスト実行・Lint・型チェック | テスト失敗、Lint エラー |
| **shellcheck** | Shell スクリプト検証 | ShellCheck エラー |
| **security-patterns** | 禁止パターン検出 | shell=True 等の検出 |
| **documentation** | ドキュメント存在確認 | 必須ドキュメント不足 |

#### 検証内容

**Python コード**:
- ✅ Black フォーマットチェック
- ✅ isort インポート順序チェック
- ✅ flake8 Lint
- ✅ mypy 型チェック
- ✅ Bandit セキュリティスキャン
- ✅ pytest テスト実行（カバレッジ付き）

**Shell スクリプト**:
- ✅ ShellCheck による静的解析

**セキュリティパターン検出**:
- ❌ `shell=True` の使用（CRITICAL）
- ❌ `os.system` の使用（CRITICAL）
- ❌ `eval` / `exec` の使用（CRITICAL）
- ❌ `bash -c` in wrappers（CRITICAL）

**ドキュメント**:
- ✅ README.md, CLAUDE.md, SECURITY.md, LICENSE の存在確認

---

### 2. Security Audit (`security-audit.yml`)

**トリガー**:
- Push（main）
- Pull Request（main）
- 毎週日曜日 0:00 UTC（定期実行）
- 手動トリガー

**目的**: 包括的なセキュリティ監査

#### Jobs

| Job | 内容 | 重要度 |
|-----|------|--------|
| **security-scan** | Bandit, Safety, pip-audit | 🔴 HIGH |
| **forbidden-patterns** | 禁止パターン検出 | 🔴 CRITICAL |
| **secrets-scan** | シークレット検出 | 🔴 HIGH |
| **sudo-security** | sudo ラッパー検証 | 🔴 HIGH |
| **report** | 監査サマリー生成 | ℹ️ INFO |

#### 禁止パターン（BLOCKING）

以下が検出された場合、ワークフローは**即座に失敗**します：

```python
# ❌ CRITICAL VIOLATIONS
subprocess.run(..., shell=True)
os.system(...)
eval(...)
exec(...)
```

```bash
# ❌ CRITICAL VIOLATIONS in wrappers
bash -c "..."
```

#### 依存関係セキュリティ

- **Safety**: 既知の脆弱性チェック
- **pip-audit**: パッケージ監査
- **truffleHog**: シークレット検出（Git 履歴含む）

---

### 3. Auto Repair (`auto-repair.yml`)

**トリガー**: 手動のみ（将来的に定期実行予定）

**目的**: 安全な自動修正（フォーマット・Lint）

#### 修復タイプ

| タイプ | 対象 | 安全性 |
|--------|------|--------|
| **format** | Black, isort | ✅ 安全 |
| **imports** | 未使用import削除 | ✅ 安全 |
| **lint** | autopep8 軽微な修正 | ⚠️ 要確認 |
| **all** | 上記すべて | ⚠️ 要確認 |

#### 動作フロー

```
CI失敗検出
  ↓
ログ解析
  ↓
自動修正適用
  ↓
Pull Request 作成
  ↓
人間レビュー（必須）
```

#### 重要な制限事項

**❌ 自動修復対象外**:
- セキュリティ関連コード
- sudo / root 権限コード
- 認証・認可ロジック
- ラッパースクリプト
- CLAUDE.md 記載の人間承認必須項目

**無限ループ防止**:
- 同一エラーでの修復は最大3回まで
- 3回失敗で人間に通知・停止

---

## 🚀 使用方法

### ローカルでの事前チェック

コミット前に以下を実行することを推奨：

```bash
# フォーマットチェック
black --check backend/
isort --check-only backend/

# Lint
flake8 backend/

# セキュリティスキャン
bandit -r backend/

# テスト
pytest tests/ -v

# Shell スクリプトチェック
shellcheck wrappers/*.sh
```

### CI が失敗した場合

1. **ローカルで再現**:
   ```bash
   # ワークフローと同じコマンドを実行
   pytest tests/ -v --cov=backend
   ```

2. **修正**:
   - フォーマット: `black backend/`
   - インポート: `isort backend/`
   - セキュリティ: CLAUDE.md 参照

3. **再実行**:
   ```bash
   git add .
   git commit -m "Fix CI issues"
   git push
   ```

### Security Audit が失敗した場合

**CRITICAL violations（shell=True 等）**:
1. 即座に修正が必要
2. CLAUDE.md のセキュリティ原則を参照
3. 修正後、Pull Request を作成

**依存関係の脆弱性**:
1. `safety check` でローカル確認
2. パッケージのアップデート検討
3. 回避策がない場合は代替パッケージを検討

### Auto Repair の使用

1. GitHub リポジトリの "Actions" タブに移動
2. "Auto Repair" ワークフローを選択
3. "Run workflow" をクリック
4. 修復タイプを選択（format / lint / all）
5. 実行後、作成された Pull Request をレビュー
6. 問題なければマージ

---

## ⚙️ ワークフローのカスタマイズ

### Python バージョン変更

`ci.yml` と `security-audit.yml`:
```yaml
- name: Set up Python
  uses: actions/setup-python@v5
  with:
    python-version: '3.11'  # ← ここを変更
```

### 定期実行の頻度変更

`security-audit.yml`:
```yaml
schedule:
  - cron: '0 0 * * 0'  # 毎週日曜日 → 変更可能
```

### Auto Repair の定期実行有効化

**⚠️ 注意**: 十分なテストと監視体制を整えてから有効化してください。

`auto-repair.yml`:
```yaml
# コメントアウトを解除
schedule:
  - cron: '*/5 * * * *'  # 5分間隔
```

---

## 📊 成功基準

### CI ワークフロー

- ✅ 全テストが pass
- ✅ カバレッジ 85%以上（目標）
- ✅ Lint エラーなし
- ✅ 型チェックエラーなし
- ✅ セキュリティパターン検出なし

### Security Audit ワークフロー

- ✅ CRITICAL violations なし
- ✅ HIGH severity issues なし
- ✅ シークレット検出なし
- ✅ ラッパースクリプト検証 pass

---

## 🔧 トラブルシューティング

### "shell=True detected" で失敗

```python
# ❌ 修正前
subprocess.run("systemctl status nginx", shell=True)

# ✅ 修正後
subprocess.run(["systemctl", "status", "nginx"])
```

### Bandit で HIGH severity

```python
# ❌ 修正前
eval(user_input)

# ✅ 修正後
# eval は使用禁止 - 代替手段を検討
```

### ShellCheck エラー

```bash
# ❌ 修正前
systemctl restart $SERVICE

# ✅ 修正後
systemctl restart "${SERVICE}"
```

---

## 📚 関連ドキュメント

- [CLAUDE.md](../../CLAUDE.md) - セキュリティ原則・開発ルール
- [SECURITY.md](../../SECURITY.md) - セキュリティポリシー
- [README.md](../../README.md) - プロジェクト概要

---

## ⚠️ 重要な注意事項

1. **CRITICAL violations は即座に修正必須**
   - PR マージ不可
   - main へのマージをブロック

2. **Auto Repair は補助ツール**
   - 最終的な判断は人間が行う
   - セキュリティ関連は自動修正対象外

3. **定期的なメンテナンス**
   - 依存関係の更新
   - ワークフローの最適化
   - セキュリティツールのバージョンアップ

---

**最終更新**: 2026-02-05

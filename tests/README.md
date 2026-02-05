# Tests - 自動テストスイート

**pytest ベースの包括的テストスイート**

---

## 📋 概要

セキュリティファースト設計を検証する自動テストスイート。

---

## 📂 構成

```
tests/
├── conftest.py                    # pytest フィクスチャ
├── unit/
│   └── test_auth.py               # 認証・認可ユニットテスト
├── integration/
│   └── test_api.py                # API統合テスト
└── security/
    └── test_security.py           # セキュリティテスト
```

---

## ✅ テスト結果

```
✅ 全32テスト PASS
📊 カバレッジ: 83.81%（目標80%達成！）
```

### カバレッジ詳細

| モジュール | カバレッジ |
|----------|----------|
| backend/api/main.py | 94.44% |
| backend/api/routes/auth.py | 100.00% ✅ |
| backend/core/config.py | 98.55% |
| backend/core/auth.py | 84.88% |

---

## 🧪 テストカテゴリ

### 1. 認証テスト (unit/test_auth.py)

- ✅ ログイン成功
- ✅ ログイン失敗（不正なメール、パスワード）
- ✅ 現在のユーザー情報取得
- ✅ 認証なしアクセス拒否

### 2. 認可テスト (unit/test_auth.py)

- ✅ Viewer はサービス再起動不可
- ✅ Operator はサービス再起動可能
- ✅ Viewer はシステム状態閲覧可能

### 3. API テスト (integration/test_api.py)

- ✅ ヘルスチェック
- ✅ 認証エンドポイント（login, me, logout）
- ✅ システムエンドポイント（認証あり/なし）
- ✅ サービスエンドポイント（権限チェック）
- ✅ ログエンドポイント（権限チェック、入力検証）

### 4. セキュリティテスト (security/test_security.py)

- ✅ shell=True 不使用検証
- ✅ os.system 不使用検証
- ✅ eval/exec 不使用検証
- ✅ bash -c 不使用検証（wrappers）
- ✅ コマンドインジェクション防止
- ✅ allowlist 検証

---

## 🚀 実行方法

### 基本的な実行

```bash
# 全テスト実行
pytest tests/ -v

# カバレッジ付き
pytest tests/ -v --cov=backend --cov-report=html

# HTMLカバレッジレポート生成
pytest tests/ --cov=backend --cov-report=html
open htmlcov/index.html
```

### カテゴリ別実行

```bash
# ユニットテストのみ
pytest tests/unit/ -v

# 統合テストのみ
pytest tests/integration/ -v

# セキュリティテストのみ
pytest tests/security/ -v
```

### マーカー別実行

```bash
# セキュリティテストのみ
pytest -m security -v

# スローテストを除外
pytest -m "not slow" -v
```

---

## 📊 CI/CD での実行

GitHub Actions では以下のコマンドで実行されます：

```bash
pytest tests/ -v --cov=backend --cov-report=html --cov-report=term
```

カバレッジが 80% 未満の場合、CI は失敗します。

---

## 📚 参考資料

- [pytest.ini](../pytest.ini) - pytest 設定
- [.coveragerc](../.coveragerc) - カバレッジ設定
- [conftest.py](./conftest.py) - フィクスチャ定義

---

**最終更新**: 2026-02-05

# Tests

pytest ベースの自動テストスイート

## 構成（予定）

```
tests/
├── test_api.py           # API エンドポイントテスト
├── test_security.py      # セキュリティテスト
├── test_wrappers.py      # wrapper 検証
└── README.md             # このファイル
```

## テストカバレッジ目標

| コンポーネント | カバレッジ目標 |
|--------------|-------------|
| backend/core/ | **90%以上** |
| backend/api/ | **85%以上** |
| wrappers/ | **100%** |

## 必須テストケース

### セキュリティテスト

```python
def test_reject_shell_injection():
    """特殊文字を含む入力を拒否すること"""
    malicious_input = "nginx; rm -rf /"
    with pytest.raises(SecurityError):
        validate_service_name(malicious_input)

def test_allowlist_only():
    """許可リスト外のサービスを拒否すること"""
    with pytest.raises(PermissionError):
        restart_service("malicious-service")
```

## 実行方法

```bash
# 全テスト実行
pytest tests/ -v

# カバレッジ付き
pytest tests/ -v --cov=backend --cov-report=html
```

詳細は [../CLAUDE.md](../CLAUDE.md) を参照してください。

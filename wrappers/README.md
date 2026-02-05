# Sudo Wrappers

sudo 経由で実行される安全なラッパースクリプト群

## 設計思想

**直接的な sudo コマンド実行を禁止し、必ずラッパー経由で実行**

### 例

```bash
# ❌ 禁止
sudo systemctl restart nginx

# ✅ 正しい
sudo /usr/local/sbin/adminui-service-restart nginx
```

## セキュリティ要件

1. **引数検証必須** - 全ての入力を検証
2. **配列渡し** - shell 展開を防止
3. **allowlist 方式** - 許可されたもののみ実行
4. **ログ記録** - 実行前後のログ

## 構成（予定）

```
wrappers/
├── adminui-status.sh              # システム状態取得
├── adminui-service-restart.sh     # サービス再起動
├── adminui-logs.sh                # ログ閲覧
└── test/
    └── test-*.sh                  # wrapper テスト
```

## sudoers 設定例

```
svc-adminui ALL=(root) NOPASSWD: /usr/local/sbin/adminui-*
```

詳細は [../CLAUDE.md](../CLAUDE.md) を参照してください。

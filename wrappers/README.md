# Sudo Wrappers

**sudo 経由で実行される安全なラッパースクリプト群**

---

## 🎯 設計思想

**直接的な sudo コマンド実行を禁止し、必ずラッパー経由で実行**

### 正しい使用例

```bash
# ❌ 禁止: 直接 sudo
sudo systemctl restart nginx

# ✅ 正しい: ラッパー経由
sudo /usr/local/sbin/adminui-service-restart.sh nginx
```

---

## 🛡️ セキュリティ原則

### 1. Allowlist 方式（最重要）

```bash
# 許可されたサービスのみ実行可能
ALLOWED_SERVICES=("nginx" "postgresql" "redis")
```

### 2. 入力検証（厳格）

```bash
# 特殊文字の完全拒否
FORBIDDEN_CHARS='[;|&$()` ><*?{}[\]]'

# 英数字・ハイフン・アンダースコアのみ許可
^[a-zA-Z0-9_-]+$
```

### 3. 配列渡し（shell 展開防止）

```bash
# ✅ 正しい
systemctl restart "${SERVICE_NAME}"

# ❌ 禁止
systemctl restart $SERVICE_NAME  # 引用符なし
```

### 4. ログ記録（全操作）

```bash
# 実行前
log "Service restart requested: service=$SERVICE_NAME, caller=$SUDO_USER"

# 成功時
log "Service restart successful: $SERVICE_NAME"

# 失敗時
error "Service restart failed: $SERVICE_NAME"
```

---

## 📂 ラッパースクリプト一覧

| スクリプト | 用途 | root権限 | 危険度 |
|----------|------|----------|--------|
| **adminui-status.sh** | システム状態取得 | 不要 | 🟢 低 |
| **adminui-service-restart.sh** | サービス再起動 | **必要** | 🟡 中 |
| **adminui-logs.sh** | ログ閲覧 | 必要 | 🟢 低 |

---

## 🚀 使用方法

### adminui-status.sh

```bash
# システム状態を JSON で取得
sudo /usr/local/sbin/adminui-status.sh

# 出力例:
# {
#   "cpu": {"usage_percent": 25.5, "cores": 4},
#   "memory": {"total": 16384, "used": 8192, "free": 8192, "usage_percent": 50.0},
#   "disk": [...],
#   "uptime": {"human_readable": "2 days", "seconds": 172800}
# }
```

### adminui-service-restart.sh

```bash
# 許可されたサービスを再起動
sudo /usr/local/sbin/adminui-service-restart.sh nginx

# 出力例（成功時）:
# {"status": "success", "service": "nginx", "before": "active", "after": "active"}

# 出力例（拒否時）:
# {"status": "error", "message": "Service not allowed: malicious-service"}
```

### adminui-logs.sh

```bash
# ログを表示（デフォルト100行）
sudo /usr/local/sbin/adminui-logs.sh nginx

# 行数指定（最大1000行）
sudo /usr/local/sbin/adminui-logs.sh nginx 500

# 出力: JSON 形式
```

---

## 🧪 テスト

### 自動テストの実行

```bash
# 全ラッパーのテストを実行
./wrappers/test/test-all-wrappers.sh

# テスト内容:
# - 正常系テスト
# - 異常系テスト（特殊文字、allowlist外）
# - セキュリティパターン検出
# - 入力検証テスト
```

---

## ⚙️ インストール

### 1. ラッパースクリプトの配置

```bash
# スクリプトを /usr/local/sbin/ にコピー
sudo cp wrappers/adminui-*.sh /usr/local/sbin/

# 所有者を root に設定
sudo chown root:root /usr/local/sbin/adminui-*.sh

# パーミッション設定（root のみ編集可能）
sudo chmod 755 /usr/local/sbin/adminui-*.sh
```

### 2. sudoers 設定

```bash
# visudo で編集
sudo visudo

# 以下を追加:
# svc-adminui ALL=(root) NOPASSWD: /usr/local/sbin/adminui-status.sh
# svc-adminui ALL=(root) NOPASSWD: /usr/local/sbin/adminui-service-restart.sh
# svc-adminui ALL=(root) NOPASSWD: /usr/local/sbin/adminui-logs.sh
```

詳細は [docs/sudoers-config.md](../docs/sudoers-config.md) を参照してください。

---

## 🔍 セキュリティチェックリスト

ラッパースクリプトが以下を満たしていることを確認：

- [x] `set -euo pipefail` が設定されている
- [x] 全ての変数が引用符で囲まれている
- [x] allowlist 方式で入力を検証
- [x] 特殊文字を完全に拒否
- [x] 配列渡しでコマンドを実行
- [x] 実行前後のログ記録
- [x] エラーハンドリングが適切
- [x] shell=True / bash -c を使用していない

---

## 📚 関連ドキュメント

- [docs/sudoers-config.md](../docs/sudoers-config.md) - sudoers 設定詳細
- [CLAUDE.md](../CLAUDE.md) - セキュリティ原則
- [test/test-all-wrappers.sh](./test/test-all-wrappers.sh) - テストスクリプト

---

**最終更新**: 2026-02-05

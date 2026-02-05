# Backend

FastAPI ベースの REST API サーバー

## 構成（予定）

```
backend/
├── api/
│   ├── routes/        # エンドポイント定義
│   ├── models/        # データモデル
│   └── main.py        # アプリケーションエントリーポイント
├── core/
│   ├── auth.py        # 認証
│   ├── permissions.py # 権限管理
│   └── audit_log.py   # 監査ログ
├── requirements.txt   # 依存関係
└── README.md          # このファイル
```

## セキュリティ原則

- **shell=True 禁止**
- **sudo は allowlist のみ**
- **全操作のログ記録**

詳細は [../CLAUDE.md](../CLAUDE.md) を参照してください。

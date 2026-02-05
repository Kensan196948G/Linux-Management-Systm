# Frontend

HTML/CSS/JavaScript ベースの WebUI

## 構成（予定）

```
frontend/
├── index.html
├── css/
│   └── style.css
├── js/
│   ├── api.js         # バックエンドAPI連携
│   ├── auth.js        # 認証
│   └── main.js        # メインロジック
└── README.md          # このファイル
```

## セキュリティ原則

- **ユーザー入力のクライアント側検証**
- **選択式UIを優先（テキスト入力最小化）**
- **特殊文字の即時拒否**

詳細は [../CLAUDE.md](../CLAUDE.md) を参照してください。

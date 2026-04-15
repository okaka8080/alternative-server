## 起動

### 初回セットアップ
```bash
# 1. 環境変数ファイルの作成
# プロジェクトルートに `.env` ファイルを作成し、以下の内容を記述してください
# APP_PORT=4000
# POSTGRES_USER=postgres
# POSTGRES_PASSWORD=postgres
# POSTGRES_PORT=5432

# 2. 依存関係のインストール
docker compose run app mix deps.get

# 3. データベースコンテナを起動(先に起動しておく)
docker compose up -d db

# 4. 少し待ってから、データベースのセットアップ(作成・マイグレーション・シード投入)
docker compose run app mix setup
```

### 起動
```bash
docker compose up -d
```

### アクセス先
- **アプリケーション**: http://localhost:4000
- **Adminer (DB管理ツール)**: http://localhost:8080
- **RedisInsight**: http://localhost:5540

### 個別でデータベース操作したい場合
```bash
# データベース作成のみ
docker compose exec app bash -c "mix ecto.create"

# マイグレーション実行のみ
docker compose exec app bash -c "mix ecto.migrate"

# シードデータ投入のみ
docker compose exec app bash -c "mix run priv/repo/seeds.exs"
```

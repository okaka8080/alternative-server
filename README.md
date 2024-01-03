## 起動
`docker compose up -d`

`docker compose exec app bash -c "mix ecto.create"`

`docker compose exec app bash -c "mix ecto.migrate"`

defmodule AlternativeServer.Repo do
  use Ecto.Repo,
    otp_app: :alternativeServer,
    adapter: Ecto.Adapters.Postgres
end

defmodule AlternativeServer.Repo.Migrations.CreateUsersCards do
  use Ecto.Migration

  def change do
    create table(:users_cards) do
      add :count, :integer
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :card_id, references(:cards, on_delete: :nothing)

      timestamps(type: :utc_datetime)
    end

    create index(:users_cards, [:user_id])
    create index(:users_cards, [:card_id])
  end
end

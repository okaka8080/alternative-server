defmodule AlternativeServer.Repo.Migrations.CreateUsersDecks do
  use Ecto.Migration

  def change do
    create table(:users_decks) do
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :deck_id, references(:decks, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:users_decks, [:user_id])
    create index(:users_decks, [:deck_id])
  end
end

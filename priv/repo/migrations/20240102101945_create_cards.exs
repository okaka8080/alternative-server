defmodule AlternativeServer.Repo.Migrations.CreateCards do
  use Ecto.Migration

  def change do
    create table(:cards) do
      add :name, :string

      timestamps(type: :utc_datetime)
    end
  end
end

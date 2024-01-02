defmodule AlternativeServer.Repo.Migrations.CreateRooms do
  use Ecto.Migration

  def change do
    create table(:rooms, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :name, :string
      add :joined_users, :integer
      add :is_active, :boolean, default: false, null: false
      add :owner_id, references(:users, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:rooms, [:owner_id])
  end
end

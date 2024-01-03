defmodule AlternativeServer.Repo.Migrations.CreateUsersRooms do
  use Ecto.Migration

  def change do
    create table(:users_rooms) do
      add :user_id, references(:users, on_delete: :nothing, type: :binary_id)
      add :room_id, references(:rooms, on_delete: :nothing, type: :binary_id)

      timestamps(type: :utc_datetime)
    end

    create index(:users_rooms, [:user_id])
    create index(:users_rooms, [:room_id])
  end
end

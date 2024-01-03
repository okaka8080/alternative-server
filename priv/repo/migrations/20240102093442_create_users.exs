defmodule AlternativeServer.Repo.Migrations.CreateUsers do
  use Ecto.Migration

  def change do
    create table(:users, primary_key: false) do
      add :id, :binary_id, primary_key: true
      add :email, :string ,null: false
      add :password, :string ,null: false
      add :name, :string ,null: false
      add :coins, :integer
      add :last_login, :naive_datetime
      add :is_deleted, :boolean, default: false, null: false

      timestamps(type: :utc_datetime)
    end
  end
end

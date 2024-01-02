defmodule AlternativeServer.User do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "users" do
    field :name, :string
    field :password, :string
    field :email, :string
    field :coins, :integer
    field :last_login, :naive_datetime
    field :is_deleted, :boolean, default: false

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(user, attrs) do
    user
    |> cast(attrs, [:email, :password, :name, :coins, :last_login,  :is_deleted])
    |> validate_required([:email, :password, :name, :coins, :last_login, :is_deleted])
  end
end

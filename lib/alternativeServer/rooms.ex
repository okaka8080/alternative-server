defmodule AlternativeServer.Rooms do
  use Ecto.Schema
  import Ecto.Changeset

  @primary_key {:id, :binary_id, autogenerate: true}
  @foreign_key_type :binary_id

  schema "rooms" do
    field :name, :string
    field :joined_users, :integer
    field :is_active, :boolean, default: false
    field :owner_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(rooms, attrs) do
    rooms
    |> cast(attrs, [:name, :joined_users, :is_active])
    |> validate_required([:name, :joined_users, :is_active])
  end
end

defmodule AlternativeServer.UsersRoom do
  use Ecto.Schema
  import Ecto.Changeset

  @foreign_key_type :binary_id

  schema "users_rooms" do

    field :user_id, :binary_id
    field :room_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(users_room, attrs) do
    users_room
    |> cast(attrs, [])
    |> validate_required([])
  end
end

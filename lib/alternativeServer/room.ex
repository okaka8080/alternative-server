defmodule AlternativeServer.Room do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias AlternativeServer.Repo

  alias AlternativeServer.Room

  @primary_key {:id, :string, autogenerate: false}
  @foreign_key_type :binary_id
  @derive {Jason.Encoder, only: [:id, :name, :password, :joined_users, :is_active, :is_public, :owner_id, :inserted_at, :updated_at]}

  schema "rooms" do
    field :name, :string
    field :password, :string
    field :joined_users, :integer
    field :is_active, :boolean, default: true
    field :is_public, :boolean, default: true
    field :owner_id, :binary_id

    timestamps(type: :utc_datetime)
  end

  def generate_room_id do
    :crypto.strong_rand_bytes(3) |> Base.encode16 |> String.downcase
  end

  @doc false
  def changeset(rooms, attrs) do
    rooms
    |> cast(attrs, [:name, :password , :joined_users, :is_public, :owner_id])
    |> validate_required([:name, :joined_users, :is_public, :owner_id])
    |> put_change(:id, generate_room_id())
  end

  @doc false
  def update_changeset(rooms, attrs) do
    rooms
    |> cast(attrs, [:joined_users, :owner_id])
    |> validate_required([:joined_users])
    |> put_change(:updated_at, DateTime.utc_now() |> DateTime.truncate(:second))
  end

  def list_rooms do
    Repo.all(Room)
  end

  def get_room(attrs) do
    Repo.get(Room, attrs)
  end

  def create_room(attrs \\ %{}) do
    %Room{}
    |> Room.changeset(attrs)
    |> Repo.insert()
  end

  def update_room(room, attrs \\ %{}) do
    room
    |> Room.update_changeset(attrs)
    |> Repo.update()
  end

  def delete_room(%Room{} = room) do
    Repo.delete(room)
  end

end

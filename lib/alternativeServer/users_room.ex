defmodule AlternativeServer.UsersRoom do
  use Ecto.Schema
  import Ecto.Changeset
  import Ecto.Query, warn: false
  alias AlternativeServer.Repo
  alias AlternativeServer.UsersRoom

  @foreign_key_type :binary_id

  schema "users_rooms" do

    field :user_id, :binary_id
    field :room_id, :string

    timestamps(type: :utc_datetime)
  end

  @doc false
  def changeset(users_room, attrs) do
    users_room
    |> cast(attrs, [])
    |> validate_required([])
  end

  def create_users_rooms(room,user) do
    %UsersRoom{user_id: user.id, room_id: room.id}
    |> Repo.insert!()
  end

  def get_users_room_by_room_id(room_id)do
    Repo.get_by(UsersRoom, room_id: room_id)
  end

  def get_users_room_by_user_id(user_id) do
    Repo.get_by(UsersRoom, user_id: user_id)
  end

  def get_next_room_host(room_id) do
    query = from r in UsersRoom,
      where: r.room_id == ^room_id,
      order_by: [asc: r.inserted_at],
      limit: 2

    case Repo.all(query) do
      [_first, second | _] -> {:ok, second}
      [_only_one] -> {:error, :not_found}
      [] -> {:error, :not_found}
    end
  end

  def delete_users_room(%UsersRoom{} = users_room) do
    Repo.delete(users_room)
  end


end

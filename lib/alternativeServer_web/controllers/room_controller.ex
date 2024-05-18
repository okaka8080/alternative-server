defmodule AlternativeServerWeb.V1.RoomController do
  use AlternativeServerWeb, :controller

  alias AlternativeServer.Accounts
  alias AlternativeServer.Room
  alias AlternativeServer.UsersRoom
  require Logger

  def getAll(conn, _params) do
    rooms = Room.list_rooms()
    json(conn, %{rooms: rooms})
  end

  def new(conn, %{"userId" => userId, "name" => name, "isPublic" => isPublic} = params) do
    password = Map.get(params, "password", "")

    if user = Accounts.get_user!(userId) do
      if result =
           Room.create_room(%{
             name: name,
             password: password,
             joined_users: 1,
             is_public: isPublic,
             owner_id: userId
           }) do
        {:ok, room} = result
        UsersRoom.create_users_rooms(room, user)

        json(conn, %{
          id: room.id
        })
      else
        conn
        |> put_status(:bad_request)
        |> put_view(AlternativeServerWeb.ErrorHTML)
        |> render(:"400")
      end
    else
      conn
      |> put_status(:unauthorized)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"401")
    end
  end

  def get(conn, %{"id" => id}) do
    if room = Room.get_room(id) do
      json(conn, %{room: room})
    else
      conn
      |> put_status(:not_found)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  def join(conn, %{"id" => id, "userId" => userId}) do
    if room = Room.get_room(id) do
      if user = Accounts.get_user!(userId) do
        if result = Room.update_room(room, %{joined_users: room.joined_users + 1}) do
          {:ok, new_room} = result
          UsersRoom.create_users_rooms(new_room, user)

          json(conn, %{
            id: new_room.id,
            user_count: new_room.joined_users
          })
        else
          conn
          |> put_status(:bad_request)
          |> put_view(AlternativeServerWeb.ErrorHTML)
          |> render(:"400")
        end
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  def exit(conn, %{"id" => id, "userId" => userId}) do
    if room = Room.get_room(id) do
      if user = Accounts.get_user!(userId) do
        # 残人数が1ならルーム削除
        if room.joined_users == 1 do
          if users_room = UsersRoom.get_users_room_by_user_id(user.id) do
            UsersRoom.delete_users_room(users_room)
            Room.delete_room(room)

            json(conn, %{
              id: room.id,
              user_count: 0
            })
          else
            conn
            |> put_status(:bad_request)
            |> put_view(AlternativeServerWeb.ErrorHTML)
            |> render(:"400")
          end
        else
          # もしルームのホストが離脱ユーザーなら
          if user.id == room.owner_id do
            room_result = UsersRoom.get_next_room_host(room.id)
            {:ok, new_users_room} = room_result
            if result = Room.update_room(room, %{joined_users: room.joined_users - 1, owner_id: new_users_room.user_id}) do
              {:ok, new_room} = result
              users_room = UsersRoom.get_users_room_by_user_id(user.id)
              UsersRoom.delete_users_room(users_room)

              json(conn, %{
                id: new_room.id,
                user_count: new_room.joined_users
              })
            else
              conn
              |> put_status(:bad_request)
              |> put_view(AlternativeServerWeb.ErrorHTML)
              |> render(:"400")
            end
          else
            # 残人数が一人以上いれば人を減らす
            if result = Room.update_room(room, %{joined_users: room.joined_users - 1}) do
              {:ok, new_room} = result
              users_room = UsersRoom.get_users_room_by_user_id(user.id)
              UsersRoom.delete_users_room(users_room)

              json(conn, %{
                id: new_room.id,
                user_count: new_room.joined_users
              })
            else
              conn
              |> put_status(:bad_request)
              |> put_view(AlternativeServerWeb.ErrorHTML)
              |> render(:"400")
            end
          end
        end
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"404")
    end
  end

  def delete(conn, %{"id" => id}) do
    if room = Room.get_room(id) do
      if users_room = UsersRoom.get_users_room_by_room_id(room.id) do
        UsersRoom.delete_users_room(users_room)
        Room.delete_room(room)
        json(conn, %{result: "delete #{room.id}"})
      else
        conn
        |> put_status(:not_found)
        |> put_view(AlternativeServerWeb.ErrorHTML)
        |> render(:"404")
      end
    else
      conn
      |> put_status(:not_found)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"404")
    end
  end
end

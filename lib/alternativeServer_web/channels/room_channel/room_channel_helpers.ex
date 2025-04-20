defmodule AlternativeServerWeb.RoomChannelHelpers do
  alias AlternativeServer.Redis
  alias AlternativeServer.Functions

  # ルームのメンバーを取得
  def get_room_members(room_id) do
    case Redis.lrange("room:#{room_id}:members", 0, -1) do
      {:ok, members} when length(members) == 2 -> {:ok, members}
      _ -> {:error, "Invalid members or count"}
    end
  end

  # 全員が待機状態かチェック
  def all_players_waiting?(room_id, members) do
    Enum.all?(members, fn user_id ->
      case Redis.get("room:#{room_id}:game:#{user_id}:is_wait") do
        {:ok, "true"} -> true
        _ -> false
      end
    end)
  end

  # フィールド情報を取得
  def get_field_positions(room_id, user_id) do
    for pos <- 1..9, into: %{} do
      case Redis.hgetall("room:#{room_id}:game:#{user_id}:field:#{pos}") do
        {:ok, pos_value} ->
          map = Functions.list_to_map(pos_value)
          {"pos#{pos}", map}

        _ ->
          nil
      end
    end
    |> Enum.reject(&is_nil/1)
    |> Enum.into(%{})
  end

  # フィールドに `is_close` があるか確認
  def has_inclose?(pos_map) do
    Enum.any?(pos_map, fn {_key, value} ->
      if map_size(value) > 0 do
        value["is_close"] == "true"
      else
        false
      end
    end)
  end

  def set_ready_status(room_id, user_id, status) do
    value = if status == true, do: "true", else: "false"
    Redis.set("room:#{room_id}:lobby:#{user_id}:is_ready", value)
  end

  def both_players_ready?(room_id, [user1, user2]) do
    with {:ok, is_ready1} <- Redis.get("room:#{room_id}:lobby:#{user1}:is_ready"),
         {:ok, is_ready2} <- Redis.get("room:#{room_id}:lobby:#{user2}:is_ready") do
      is_ready1 == "true" and is_ready2 == "true"
    else
      _ -> false
    end
  end

  def reset_ready_status(room_id, [user1, user2]) do
    Redis.set("room:#{room_id}:lobby:#{user1}:is_ready", "false")
    Redis.set("room:#{room_id}:lobby:#{user2}:is_ready", "false")
  end

  def set_ready_and_check(room_id, user_id, status) do
    set_ready_status(room_id, user_id, status)

    case get_room_members(room_id) do
      {:ok, [user1, user2]} ->
        if both_players_ready?(room_id, [user1, user2]) do
          reset_ready_status(room_id, [user1, user2])
          {:ok, true}
        else
          {:ok, false}
        end

      _ ->
        {:error, :members_not_found}
    end
  end

end

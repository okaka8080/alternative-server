defmodule AlternativeServerWeb.RoomChannel do
  use Phoenix.Channel
  alias AlternativeServer.DuelSystem
  alias AlternativeServer.Accounts
  alias AlternativeServer.Redis
  alias AlternativeServer.Functions
  require Logger

  @doc """
  WebSocket用の関数
  """
  def join("room:lobby", _message, socket) do
    {:ok, socket}
  end

  def join("room:" <> private_room_id, params, socket) do
    case authenticate(params) do
      {:ok, user} ->
        # Redisのルーム初期化
        Redis.setnx("room:#{private_room_id}:lobby:readyCount", "0")
        send(self(), {:after_join, %{user_id: user.id, user_name: user.name}})
        {:ok, assign(socket, :user_assign, %{user: user, room_id: private_room_id})}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def authenticate(params) do
    token = params["token"]
    Logger.info("token is #{token}")

    if user = Accounts.get_user_by_session_token(token |> Base.decode64!()) do
      Logger.info("joined user is #{user.name}")
      {:ok, %{id: user.id, name: user.name}}
    else
      Logger.error("joined user is not found")
      {:error, %{reason: "unauthorized"}}
    end
  end

  defp get_room_members(room_id) do
    case Redis.lrange("room:#{room_id}:members", 0, -1) do
      {:ok, members} when length(members) == 2 -> {:ok, members}
      _ -> {:error, "Invalid members or count"}
    end
  end

  defp all_players_waiting?(room_id, members) do
    Enum.all?(members, fn user_id ->
      case Redis.get("room:#{room_id}:game:#{user_id}:is_wait") do
        {:ok, "true"} -> true
        _ -> false
      end
    end)
  end

  # ヘルパー関数: フィールド情報を取得
  defp get_field_positions(room_id, user_id) do
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

  # ヘルパー関数: フィールドに `is_close` があるか確認
  defp has_inclose?(pos_map) do
    Enum.any?(pos_map, fn {_key, value} ->
      if map_size(value) > 0 do
        value["is_close"] == "true"
      else
        false
      end
    end)
  end

  def handle_in("new_msg", %{"body" => body}, socket) do
    broadcast!(socket, "new_msg", %{body: body})
    {:noreply, socket}
  end

  def handle_in("set_ready", %{"user_id" => user_id, "status" => status}, socket) do
    new_assign = Map.put(socket.assigns.user_assign, "status", status)
    socket = assign(socket, :user_assign, new_assign)
    broadcast!(socket, "set_ready", %{user_id: user_id, status: status})
    {:noreply, socket}
    Logger.info("message from: #{user_id}")
    Logger.info(socket.assigns.user_assign.room_id)

    if status == true do
      {:ok, number} = Redis.incr("room:#{socket.assigns.user_assign.room_id}:lobby:readyCount")
      Logger.info("incr to #{number}")
    else
      Redis.decr("room:#{socket.assigns.user_assign.room_id}:lobby:readyCount")
    end

    case Redis.get("room:#{socket.assigns.user_assign.room_id}:lobby:readyCount") do
      {:ok, readyCount} when readyCount == "2" ->
        Logger.info("readyCount is 2")
        broadcast!(socket, "duel_start", %{status: true})
        Redis.set("room:#{socket.assigns.user_assign.room_id}:lobby:readyCount", "0")
        {:noreply, socket}

      {:ok, readyCount} when readyCount != "2" ->
        Logger.info("readyCount is not 2, it's #{readyCount}")
        broadcast!(socket, "duel_start", %{status: false})
        {:noreply, socket}

      _ ->
        Logger.info("did not receive {:ok, readyCount} tuple")
        broadcast!(socket, "duel_start", %{status: false})
        {:noreply, socket}
    end
  end

  # デュエルセッション開始
  def handle_in("finish_ready", %{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    room_id = socket.assigns.user_assign.room_id
    # TODO セッション管理追加

    # ルームの初期化
    Redis.lpush("room:#{room_id}:members", user_id)
    Redis.hset("room:#{room_id}:game:state", "turn", 1)
    Redis.hset("room:#{room_id}:game:state", "phase", 0)
    Redis.hset("room:#{room_id}:game:state", "phase_state", 0)

    # ゲームの初期化
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "sp", 5)
    # TODO: LPはデッキの値から取得してくる
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "lp", 7)
    # TODO: apを初期化

    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", 0)
    Redis.set("room:#{room_id}:game:#{user_id}:status:next_card", 0)

    # プレイヤーを待機状態に遷移
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  # セットフェイズ：カード選択
  def handle_in("select_card", %{"user_id" => user_id} = params, socket) do
    # 各種値を取得
    ap = Map.get(params, "ap", nil)
    sp = Map.get(params, "sp", nil)
    card_id = Map.get(params, "card_id", nil)
    room_id = socket.assigns.user_assign.room_id

    Logger.info("#{user_id}, #{card_id}, #{ap}, #{sp}")

    # Redisに保存
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "sp", sp)
    # TODO: APの値保存方法 要検討
    Enum.each(ap, fn x ->
      Redis.rpush("room:#{room_id}:game:#{user_id}:status:ap", x)
    end)
    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", card_id)

    # プレイヤーを待機状態に遷移
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  # セットフェイズ：カード配置
  def handle_in("set_card", %{"user_id" => user_id, "set_pos" => set_pos}, socket) do
    room_id = socket.assigns.user_assign.room_id
    # Redisからカード情報を取得
    {:ok, set_card} = Redis.get("room:#{room_id}:game:#{user_id}:status:set_card")
    Logger.info("set card is #{set_card}")
    # TODO: カードの情報を取得

    card_data = %{
      card_id: set_card,
      # あとあと、カードステータスもいれる
      is_active: false,
      is_close: false,
      # ここからスタッツ
      hp: 20,
      level: 1,
      attack: 10,
      speed: 1,
      range: 1
    }

    IO.inspect(card_data, label: "Card Data")

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:field:#{set_pos}",
      "card_id",
      card_data.card_id
    )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:field:#{set_pos}",
      "is_active",
      card_data.is_active
    )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:field:#{set_pos}",
      "is_close",
      card_data.is_close
    )

    # 次のターンのセットカードを保存
    Redis.hset(
      "room:#{room_id}:game:#{user_id}:status:next_card",
      "card_id",
      set_card
    )
    Redis.hset(
      "room:#{room_id}:game:#{user_id}:status:next_card",
      "set_pos",
      set_pos
    )

    # プレイヤーを待機状態に遷移
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    # set_cardを初期化
    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", 0)

    IO.puts("Card data set successfully")
    {:noreply, socket}
  end

  def handle_in("open_skill_end", %{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  def handle_in("open_phase_end", %{"user_id" => user_id}, socket) do
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  def handle_in("check_wait", %{"type" => type}, socket) do
    room_id = socket.assigns.user_assign.room_id
    {:ok, turn} = Redis.hget("room:#{room_id}:game:state", "turn")
    {:ok, phase} = Redis.hget("room:#{room_id}:game:state", "phase")
    {:ok, phase_state} = Redis.hget("room:#{room_id}:game:state", "phase_state")
    Logger.info("check_start")

    case type do
      0 ->
        # 準備完了
        Logger.info("check to finish_ready")

        with {:ok, members} <- get_room_members(room_id),
           true <- all_players_waiting?(room_id, members) do
          Logger.info("Both players are ready. Broadcasting transition.")
          broadcast(socket, "transition", %{status: true})
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            broadcast(socket, "transition", %{status: false})
        end

        {:noreply, socket}
      1 ->
        # セットフェイズ・カードセット
        Logger.info("check to select_card")

        case get_room_members(room_id) do
          {:ok, [id1, id2]} ->
            if all_players_waiting?(room_id, [id1, id2]) do
              Logger.info("Both players have selected cards.")

              # 各プレイヤーのカード情報を取得
              {:ok, sp1} = Redis.hget("room:#{room_id}:game:#{id1}:status", "sp")
              {:ok, ap1} = Redis.lrange("room:#{room_id}:game:#{id1}:status:ap", 0, -1)
              {:ok, card1} = Redis.get("room:#{room_id}:game:#{id1}:status:set_card")

              {:ok, sp2} = Redis.hget("room:#{room_id}:game:#{id2}:status", "sp")
              {:ok, ap2} = Redis.lrange("room:#{room_id}:game:#{id2}:status:ap", 0, -1)
              {:ok, card2} = Redis.get("room:#{room_id}:game:#{id2}:status:set_card")

              # データ構造を作成
              data1 = %{
                user_id: id1,
                card_id: card1,
                sp: sp1,
                ap: ap1
              }

              data2 = %{
                user_id: id2,
                card_id: card2,
                sp: sp2,
                ap: ap2
              }

              # カード選択完了をクライアントに通知
              broadcast(socket, "cardSelect", %{
                status: true,
                user1: data1,
                user2: data2,
                first_user_id: id1
              })

              # 両プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              {:noreply, socket}
            else
              Logger.info("Players are not ready or failed to fetch is_wait status.")
              broadcast(socket, "cardSelect", %{status: false})
              {:noreply, socket}
            end

          _ ->
            Logger.info("Failed to fetch room members or invalid member count.")
            broadcast(socket, "cardSelect", %{status: false})
            {:noreply, socket}

        {:noreply, socket}
        end

      2 ->
        #  セットフェイズ・配置
        Logger.info("check to set card position")

        case get_room_members(room_id) do
          {:ok, [id1, id2]} ->
            if all_players_waiting?(room_id, [id1, id2]) do
              # 両プレイヤーのフィールド情報を取得
              pos_map_1 = get_field_positions(room_id, id1)
              pos_map_2 = get_field_positions(room_id, id2)

              # 次に配置するカード情報を取得
              {:ok, entry_card1} = Redis.hgetall("room:#{room_id}:game:#{id1}:next_card")
              {:ok, entry_card2} = Redis.hgetall("room:#{room_id}:game:#{id2}:next_card")

              # フィールドに `is_close` があるか確認
              has_inclose1 = has_inclose?(pos_map_1)
              has_inclose2 = has_inclose?(pos_map_2)

              if has_inclose1 || has_inclose2 do
                # 蘇生フェイズに移行
                user1 = %{user_id: id1, is_close: has_inclose1}
                user2 = %{user_id: id2, is_close: has_inclose2}

                broadcast(socket, "revivalPhaseStart", %{
                  status: true,
                  user1: user1,
                  user2: user2,
                  next_state: 2
                })
              else
                # カード情報を送信
                field1 = %{user_id: id1, pos: pos_map_1, new_entry_card: entry_card1}
                field2 = %{user_id: id2, pos: pos_map_2, new_entry_card: entry_card2}

                Logger.info("field_1 is #{inspect(field1)}")
                Logger.info("field_2 is #{inspect(field2)}")

                broadcast(socket, "startViewCards", %{
                  status: true,
                  field1: field1,
                  field2: field2,
                  next_state: 3
                })
              end

              # 両プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              {:noreply, socket}
            end
          _ ->
            Logger.info("Players are not ready or failed to fetch is_wait status.")
            broadcast(socket, "startViewCards", %{status: false})
            {:noreply, socket}
        end

      3 ->
        # セットフェイズ・復活選択
        Logger.info("check to revival card")

      4 ->
        Logger.info("check to revival card")

      # セットフェイズ・次のPhaseState指定

      # セットカードの有無(固有)

      # 復活カードの有無(リスト参照)

      5 ->
        # オープン完了後待機処理
        Logger.info("check to openSkillEnd")

      6 ->
        # オープン完了後待機処理
        Logger.info("check to openPhaseEnd")

        with {:ok, [id1, id2]} <- get_room_members(room_id),
           true <- all_players_waiting?(room_id, [id1, id2]) do

             # フィールドのカードの枚数を取得 ->　お互い0ならアクションフェイズスキップ

             if String.to_integer(turn) == 1 do
              Logger.info("next phase is turn end")
              DuelSystem.change_turn(room_id)
              # プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              broadcast(socket, "turnEnd", %{status: true})
              {:noreply, socket}
            else
              Logger.info("next phase is action phase")

              # プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              broadcast(socket, "openPhaseEnd", %{status: true})
              {:noreply, socket}
            end
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            broadcast(socket, "openPhaseEnd", %{status: false})
        end

      7 ->
        #  アクションフェイズ
        Logger.info("check to set card position")

        with {:ok, members} <- get_room_members(room_id),
           true <- all_players_waiting?(room_id, members) do
            broadcast(socket, "actionPhaseEnd", %{status: true})
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            broadcast(socket, "actionPhaseEnd", %{status: false})
        end

        {:noreply, socket}
    end

    {:noreply, socket}
  end

  def handle_info({:after_join, user}, socket) do
    broadcast(socket, "user_joined", user)
    Logger.info("user is #{user.user_id}, #{user.user_name}")
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    broadcast!(socket, "user_left", %{user_id: socket.assigns.user_assign.user.id})
  end

  # intercept ["user_joined"]

  # def handle_out("user_joined", msg, socket) do
  #   if Accounts.ignoring_user?(socket.assigns[:user], msg.user_id) do
  #     {:noreply, socket}
  #   else
  #     push(socket, "user_joined", msg)
  #     {:noreply, socket}
  #   end
  # end
end

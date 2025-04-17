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

  def handle_in("finish_ready", %{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    Redis.incr("room:#{socket.assigns.user_assign.room_id}:game:transitionCount")
    Redis.lpush("room:#{socket.assigns.user_assign.room_id}:members", user_id)
    Redis.set("room:#{socket.assigns.user_assign.room_id}:game:currentTurn", 1)
    Redis.set("room:#{socket.assigns.user_assign.room_id}:game:currentPhase", 0)
    Redis.set("room:#{socket.assigns.user_assign.room_id}:game:phaseState", 0)
    {:noreply, socket}
  end

  def handle_in("select_card", %{"user_id" => user_id} = params, socket) do
    ap = Map.get(params, "ap", nil)
    sp = Map.get(params, "sp", nil)
    card_id = Map.get(params, "card_id", nil)
    room_id = socket.assigns.user_assign.room_id
    Logger.info("#{user_id}, #{card_id}, #{ap}, #{sp}")

    Redis.set("room:#{room_id}:game:#{user_id}:sp", sp)

    # Redis.set("room:#{room_id}:game:#{user_id}:ap", ap)

    Enum.each(ap, fn x ->
      Redis.rpush("room:#{room_id}:game:#{user_id}:ap", x)
    end)

    # Redis.lpush("room:#{room_id}:game:#{user_id}:ap", ap[0])

    Redis.set("room:#{room_id}:game:#{user_id}:setCard", card_id)
    Redis.setnx("room:#{room_id}:game:selectCardCount", 0)
    Redis.incr("room:#{room_id}:game:selectCardCount")
    {:noreply, socket}
  end

  def handle_in("set_card", %{"user_id" => user_id, "set_pos" => set_pos}, socket) do
    # user_idからsetしてるカードを取得して配置
    room_id = socket.assigns.user_assign.room_id
    {:ok, set_card} = Redis.get("room:#{room_id}:game:#{user_id}:setCard")

    Logger.info("set card is #{set_card}")

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
      "room:#{room_id}:game:#{user_id}:fieldCards:#{set_pos}",
      "card_id",
      card_data.card_id
    )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:fieldCards:#{set_pos}",
      "is_active",
      card_data.is_active
    )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:fieldCards:#{set_pos}",
      "is_close",
      card_data.is_close
    )

    # 次のターンのセットカードを保存
    # Redis.hset(
    #   "room:#{room_id}:game:#{user_id}:nextSetCard",
    #   "user_id",
    #   user_id
    # )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:nextSetCard",
      "card_id",
      set_card
    )

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:nextSetCard",
      "set_pos",
      set_pos
    )

    Redis.setnx("room:#{room_id}:game:setCardCount", 0)
    Redis.incr("room:#{room_id}:game:setCardCount")
    Redis.set("room:#{room_id}:game:#{user_id}:setCard", 0)
    IO.puts("Card data set successfully")

    {:noreply, socket}
  end

  def handle_in("open_skill_end", %{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    Redis.incr("room:#{socket.assigns.user_assign.room_id}:game:openSkillEndCount")
    {:noreply, socket}
  end

  def handle_in("open_phase_end", %{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    Redis.incr("room:#{socket.assigns.user_assign.room_id}:game:openPhaseEndCount")
    {:noreply, socket}
  end

  def handle_in("check_wait", %{"type" => type}, socket) do
    room_id = socket.assigns.user_assign.room_id
    {:ok, current_turn} = Redis.get("room:#{room_id}:game:currentTurn")
    Logger.info("check_start")

    case type do
      0 ->
        # 準備完了
        Logger.info("check to finish_ready")

        case Redis.get("room:#{room_id}:game:transitionCount") do
          {:ok, result} when result == "2" ->
            Logger.info("transitionCount is 2")
            broadcast(socket, "transition", %{status: true})
            Redis.set("room:#{room_id}:game:transitionCount", 0)
            {:noreply, socket}

          _ ->
            Logger.info("transition failed")
            broadcast(socket, "transition", %{status: false})
            {:noreply, socket}
        end

      1 ->
        # セットフェイズ・カードセット
        Logger.info("check to select_card")

        case Redis.get("room:#{room_id}:game:selectCardCount") do
          {:ok, result} when result == "2" ->
            Logger.info("selectCardCount is 2")

            case Redis.lrange("room:#{room_id}:members", 0, 1) do
              {:ok, members} ->
                id1 = Enum.at(members, 0)
                id2 = Enum.at(members, 1)

                # sp,ap,card情報を取得
                {:ok, sp1} = Redis.get("room:#{room_id}:game:#{id1}:sp")
                {:ok, ap1} = Redis.lrange("room:#{room_id}:game:#{id1}:ap", 0, 3)
                {:ok, card1} = Redis.get("room:#{room_id}:game:#{id1}:setCard")
                {:ok, sp2} = Redis.get("room:#{room_id}:game:#{id2}:sp")
                {:ok, ap2} = Redis.lrange("room:#{room_id}:game:#{id2}:ap", 0, 3)
                {:ok, card2} = Redis.get("room:#{room_id}:game:#{id2}:setCard")

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

                broadcast(socket, "cardSelect", %{
                  status: true,
                  user1: data1,
                  user2: data2,
                  first_user_id: id1
                })

                # カウントリセット
                Redis.set("room:#{room_id}:game:selectCardCount", 0)

                {:noreply, socket}
            end

            {:noreply, socket}

          _ ->
            Logger.info("set_card failed")
            broadcast(socket, "cardSelect", %{status: false, data: nil})
            {:noreply, socket}
        end

      2 ->
        #  セットフェイズ・配置
        Logger.info("check to set card position")

        Logger.info("current turn is #{current_turn}")

        case Redis.get("room:#{room_id}:game:setCardCount") do
          {:ok, result} when result == "2" ->
            Logger.info("setCardCount is 2")

            case Redis.lrange("room:#{room_id}:members", 0, 1) do
              {:ok, members} ->
                id1 = Enum.at(members, 0)
                id2 = Enum.at(members, 1)
                pos_map_1 =
                  for pos <- 1..9, into: %{} do
                    case Redis.hgetall("room:#{room_id}:game:#{id1}:fieldCards:#{pos}") do
                      {:ok, pos_value} ->
                        map = Functions.list_to_map(pos_value)
                        {"pos#{pos}", map}

                      _ ->
                        nil
                    end
                  end
                  |> Enum.reject(&is_nil/1)
                  |> Enum.into(%{})

                IO.puts(inspect(pos_map_1))

                {:ok, entry_card1} = Redis.hgetall("room:#{room_id}:game:#{id1}:nextSetCard")

                pos_map_2 =
                  for pos <- 1..9, into: %{} do
                    case Redis.hgetall("room:#{room_id}:game:#{id2}:fieldCards:#{pos}") do
                      {:ok, pos_value} ->
                        map = Functions.list_to_map(pos_value)
                        {"pos#{pos}", map}

                      _ ->
                        nil
                    end
                  end
                  |> Enum.reject(&is_nil/1)
                  |> Enum.into(%{})

                IO.puts(inspect(pos_map_2))

                {:ok, entry_card2} = Redis.hgetall("room:#{room_id}:game:#{id2}:nextSetCard")

                has_inclose1 =
                  Enum.any?(pos_map_1, fn {key, value} ->
                    if map_size(value) > 0 do
                      IO.puts("#{key} has is_close value: #{value[:is_close]}")
                      value[:is_close] == true
                    else
                      IO.puts("#{key} is empty")
                      false
                    end
                  end)

                has_inclose2 =
                  Enum.any?(pos_map_2, fn {key, value} ->
                    if map_size(value) > 0 do
                      IO.puts("#{key} has is_close value: #{value[:is_close]}")
                      value[:is_close] == true
                    else
                      IO.puts("#{key} is empty")
                      false
                    end
                  end)

                # カウントリセット
                Redis.set("room:#{room_id}:game:setCardCount", 0)

                if has_inclose1 || has_inclose2 do
                  # このタイミングで蘇生するフェイズに入るか送信する
                  user1 = %{
                    user_id: id1,
                    is_close: has_inclose1
                  }

                  user2 = %{
                    user_id: id2,
                    is_close: has_inclose2
                  }

                  broadcast(socket, "revivalPhaseStart", %{status: true, user1: user1, user2: user2, next_state: 2})
                  {:noreply, socket}
                else
                  # このタイミングでカードも送信する
                  field1 = %{
                    user_id: id1,
                    pos: pos_map_1,
                    new_entry_card: entry_card1
                  }
                  field2 = %{
                    user_id: id2,
                    pos: pos_map_2,
                    new_entry_card: entry_card2
                  }

                  Logger.info("field_1 is #{inspect(field1)}")
                  Logger.info("field_2 is #{inspect(field2)}")

                  broadcast(socket, "startViewCards", %{status: true, field1: field1, field2: field2, next_state: 3})
                  {:noreply, socket}
                end
            end

            {:noreply, socket}

          _ ->
            Logger.info("setCardCount failed")
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

        case Redis.get("room:#{room_id}:game:openSkillEndCount") do
          {:ok, result} when result == "2" ->
            Logger.info("openSkillEndCount is 2")

          {:ok, result} when result == "1" ->
            Logger.info("openSkillEndCount is 1")

          # 相手の処理が完了している->自分の処理に変更

          # カウントリセット
          Redis.set("room:#{room_id}:game:openSkillEndCount", 0)

          _ ->
            Logger.info("openSkillEndCount failed")
            {:noreply, socket}
        end

      6 ->
        # オープン完了後待機処理
        Logger.info("check to openPhaseEnd")

        case Redis.get("room:#{room_id}:game:openPhaseEndCount") do
          {:ok, result} when result == "2" ->
            Logger.info("openPhaseEndCount is 2")

            # フィールドのカードの枚数を取得 ->　お互い0ならアクションフェイズスキップ
            case Redis.lrange("room:#{room_id}:members", 0, 1) do
              {:ok, members} ->
                # id1 = Enum.at(members, 0)
                # id2 = Enum.at(members, 1)

                if String.to_integer(current_turn) == 1 do
                  Logger.info("next phase is turn end")
                  DuelSystem.change_turn(room_id)
                  # カウントリセット
                  Redis.set("room:#{room_id}:game:openPhaseEndCount", 0)
                  broadcast(socket, "turnEnd", %{status: true})
                  {:noreply, socket}
                else
                  Logger.info("next phase is action phase")

                  # カウントリセット
                  Redis.set("room:#{room_id}:game:openPhaseEndCount", 0)

                  broadcast(socket, "openPhaseEnd", %{status: true})
                  {:noreply, socket}
                end
            end

            # Redis.set("room:#{room_id}:game:transitionCount", "0")
            {:noreply, socket}

          _ ->
            Logger.info("openPhaseEndCount failed")
            {:noreply, socket}
        end

      7 ->
        #  アクションフェイズ
        Logger.info("check to set card position")

        case Redis.get("room:#{room_id}:game:setCardCount") do
          {:ok, result} when result == "2" ->
            Logger.info("setCardCount is 2")

            # この辺やる

            {:noreply, socket}

          _ ->
            Logger.info("action phase failed")
            {:noreply, socket}
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

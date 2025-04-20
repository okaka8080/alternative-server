defmodule AlternativeServerWeb.RoomChannelGame do
  alias AlternativeServer.Redis
  alias AlternativeServerWeb.RoomChannelHelpers
  alias AlternativeServer.Functions
  alias AlternativeServer.DuelSystem
  require Logger

  @doc """
  set_readyのロジックをまとめる
  """
  def set_ready_logic(room_id, user_id, status) do
    RoomChannelHelpers.set_ready_status(room_id, user_id, status)

    case RoomChannelHelpers.get_room_members(room_id) do
      {:ok, [user1, user2]} ->
        if RoomChannelHelpers.both_players_ready?(room_id, [user1, user2]) do
          RoomChannelHelpers.reset_ready_status(room_id, [user1, user2])
          {:ok, :both_ready}
        else
          {:ok, :not_ready}
        end

      _ ->
        {:error, :members_not_found}
    end
  end

  # デュエルセッション開始
  def finish_ready(%{"user_id" => user_id}, socket) do
    room_id = socket.assigns.user_assign.room_id

    Redis.hset("room:#{room_id}:game:state", "turn", 1)
    Redis.hset("room:#{room_id}:game:state", "phase", 0)
    Redis.hset("room:#{room_id}:game:state", "phase_state", 0)

    # ゲームの初期化
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "sp", 5)
    # TODO: LPはデッキの値から取得してくる
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "lp", 7)
    # TODO: apを初期化

    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", 0)
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  # セットフェイズ：カード選択
  def select_card(%{"user_id" => user_id} = params, socket) do
    ap = Map.get(params, "ap", nil)
    sp = Map.get(params, "sp", nil)
    card_id = Map.get(params, "card_id", nil)
    room_id = socket.assigns.user_assign.room_id

    Logger.info("#{user_id}, #{card_id}, #{ap}, #{sp}")

    Redis.hset("room:#{room_id}:game:#{user_id}:status", "sp", sp)
    # TODO: APの値保存方法 要検討
    Enum.each(ap, fn x ->
      Redis.rpush("room:#{room_id}:game:#{user_id}:status:ap", x)
    end)

    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", card_id)
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  # セットフェイズ：カード配置
  def set_card(%{"user_id" => user_id, "set_pos" => set_pos}, socket) do
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

    # 次のターンのセットカードを保存
    Redis.hset(
      "room:#{room_id}:game:#{user_id}:status:next_card",
      %{
        "set_pos" => set_pos,
        "card_id" => card_data["card_id"],
        "is_active" => card_data["is_active"],
        "is_close" => card_data["is_close"],
        "hp" => card_data["hp"],
        "level" => card_data["level"],
        "attack" => card_data["attack"],
        "speed" => card_data["speed"],
        "range" => card_data["range"]
      }
    )

    # プレイヤーを待機状態に遷移
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    # set_cardを初期化
    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", 0)

    IO.puts("Card data set successfully")
    {:noreply, socket}
  end

  def open_skill_end(%{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  def open_phase_end(%{"user_id" => user_id}, socket) do
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    {:noreply, socket}
  end

  def check_wait(type, room_id) do
    {:ok, turn} = Redis.hget("room:#{room_id}:game:state", "turn")
    {:ok, _phase} = Redis.hget("room:#{room_id}:game:state", "phase")
    {:ok, _phase_state} = Redis.hget("room:#{room_id}:game:state", "phase_state")
    Logger.info("check_start")

    case type do
      0 ->
        # 準備完了
        Logger.info("check to finish_ready")

        with {:ok, [id1, id2]} <- RoomChannelHelpers.get_room_members(room_id),
             true <- RoomChannelHelpers.all_players_waiting?(room_id, [id1, id2]) do
          Logger.info("Both players are ready. Broadcasting transition.")
          # 両プレイヤーの `is_wait` をリセット
          Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
          Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

          {:ok, :transition, %{status: true}}
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            {:errror, :transition, %{status: false}}
        end

      1 ->
        # セットフェイズ・カードセット
        Logger.info("check to select_card")

        case RoomChannelHelpers.get_room_members(room_id) do
          {:ok, [id1, id2]} ->
            if RoomChannelHelpers.all_players_waiting?(room_id, [id1, id2]) do
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

              # 両プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              # カード選択完了をクライアントに通知
              {:ok, :cardSelect,
               %{
                 status: true,
                 user1: data1,
                 user2: data2,
                 first_user_id: id1
               }}
            else
              Logger.info("Players are not ready or failed to fetch is_wait status.")
              {:errror, :cardSelect, %{status: false}}
            end

          _ ->
            Logger.info("Failed to fetch room members or invalid member count.")
            {:errror, :cardSelect, %{status: false}}
        end

      2 ->
        #  セットフェイズ・配置
        Logger.info("check to set card position")

        case RoomChannelHelpers.get_room_members(room_id) do
          {:ok, [id1, id2]} ->
            if RoomChannelHelpers.all_players_waiting?(room_id, [id1, id2]) do
              # 両プレイヤーのフィールド情報を取得
              pos_map_1 = RoomChannelHelpers.get_field_positions(room_id, id1)
              pos_map_2 = RoomChannelHelpers.get_field_positions(room_id, id2)

              # 配置フェイズでの取得部分
              {:ok, entry_card1} = Redis.hgetall("room:#{room_id}:game:#{id1}:status:next_card")
              {:ok, entry_card2} = Redis.hgetall("room:#{room_id}:game:#{id2}:status:next_card")

              # ここでリスト→Mapに変換
              entry_card1_map = Functions.list_to_map(entry_card1)
              entry_card2_map = Functions.list_to_map(entry_card2)

              # フィールドに `is_close` があるか確認
              has_inclose1 = RoomChannelHelpers.has_inclose?(pos_map_1)
              has_inclose2 = RoomChannelHelpers.has_inclose?(pos_map_2)

              # 両プレイヤーの `is_wait` をリセット
              Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
              Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

              if has_inclose1 || has_inclose2 do
                # 蘇生フェイズに移行
                user1 = %{user_id: id1, is_close: has_inclose1}
                user2 = %{user_id: id2, is_close: has_inclose2}

                {:ok, :revivalPhaseStart,
                 %{
                   status: true,
                   user1: user1,
                   user2: user2,
                   next_state: 2
                 }}
              else
                # カード情報を送信
                field1 = %{user_id: id1, pos: pos_map_1, entry_card: entry_card1_map}
                field2 = %{user_id: id2, pos: pos_map_2, entry_card: entry_card2_map}

                Logger.info("field_1 is #{inspect(field1)}")
                Logger.info("field_2 is #{inspect(field2)}")

                # フィールド情報をクライアントに送信
                {:ok, :startViewCards,
                 %{
                   status: true,
                   field1: field1,
                   field2: field2,
                   next_state: 3
                 }}
              end
            end

          _ ->
            Logger.info("Players are not ready or failed to fetch is_wait status.")
            {:errror, :startViewCards, %{status: false}}
        end

      3 ->
        # セットフェイズ・復活選択
        Logger.info("check to revival card")

      4 ->
        Logger.info("check to revival card")

      5 ->
        # オープン完了後スキル待機処理
        Logger.info("check to openSkillEnd")

      6 ->
        # オープン完了後待機処理
        Logger.info("check to openPhaseEnd")

        with {:ok, [id1, id2]} <- RoomChannelHelpers.get_room_members(room_id),
             true <- RoomChannelHelpers.all_players_waiting?(room_id, [id1, id2]) do
          # エントリーカード取得
          {:ok, entry_card1} = Redis.hgetall("room:#{room_id}:game:#{id1}:status:next_card")
          {:ok, entry_card2} = Redis.hgetall("room:#{room_id}:game:#{id2}:status:next_card")
          # ここでリスト→Mapに変換
          entry_card1_map = Functions.list_to_map(entry_card1)
          entry_card2_map = Functions.list_to_map(entry_card2)
          # エントリーカードをフィールドに追加
          DuelSystem.hset_newCard(room_id, id1, entry_card1_map)
          DuelSystem.hset_newCard(room_id, id2, entry_card2_map)
          # エントリーカードを初期化
          Redis.hreset("room:#{room_id}:game:#{id1}:status:next_card")
          Redis.hreset("room:#{room_id}:game:#{id2}:status:next_card")

          # フィールドのカードの枚数を取得 ->　お互い0ならアクションフェイズスキップ

          if String.to_integer(turn) == 1 do
            Logger.info("next phase is turn end")
            DuelSystem.change_turn(room_id)
            # プレイヤーの `is_wait` をリセット
            Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
            Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

            {:ok, :turnEnd, %{status: true}}
          else
            Logger.info("next phase is action phase")

            # プレイヤーの `is_wait` をリセット
            Redis.set("room:#{room_id}:game:#{id1}:is_wait", "false")
            Redis.set("room:#{room_id}:game:#{id2}:is_wait", "false")

            {:ok, :openPhaseEnd, %{status: true}}
          end
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            {:error, :openPhaseEnd, %{status: false}}
        end

      7 ->
        #  アクションフェイズ・終了
        Logger.info("check to actionPhaseEnd")

        with {:ok, members} <- RoomChannelHelpers.get_room_members(room_id),
             true <- RoomChannelHelpers.all_players_waiting?(room_id, members) do
          {:ok, :actionPhaseEnd, %{status: true}}
        else
          _ ->
            Logger.info("Players are not ready or failed to fetch members.")
            {:error, :actionPhaseEnd, %{status: false}}
        end
    end
  end
end

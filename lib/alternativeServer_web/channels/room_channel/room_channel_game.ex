defmodule AlternativeServerWeb.RoomChannelGame do
  alias AlternativeServer.Redis
  alias AlternativeServerWeb.RoomChannelHelpers
  alias AlternativeServer.GameServerManager
  alias AlternativeServer.Game.GameServer
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

    # デバッグ用ログを追加
    Logger.info("=== FINISH_READY DEBUG START ===")
    Logger.info("Room ID: #{room_id}")
    Logger.info("User ID: #{user_id}")
    Logger.info("Channel topic: #{socket.topic}")

    # GameServerが起動していなければ起動
    _start_result =
      case GameServerManager.start_game_server(room_id) do
        {:ok, pid} when is_pid(pid) ->
          Logger.info("GameServer started/found for room: #{room_id}, PID: #{inspect(pid)}")
          :ok

        {:ok, :already_started} ->
          Logger.info("GameServer already running for room: #{room_id}")
          :ok

        {:error, reason} ->
          Logger.error(
            "Failed to start GameServer for room: #{room_id}, reason: #{inspect(reason)}"
          )

          # エラーの場合も処理を継続する
          :error
      end

    # 従来のRedis初期化処理（とりあえず残しておく）
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

    # プレイヤーをGameServerに追加
    GameServer.add_player(room_id, user_id)

    # Task.startを使って非同期でready状態を通知
    Task.start(fn ->
      GameServer.player_action(room_id, user_id, :ready)
    end)

    {:noreply, socket}
  end

  # セットフェイズ：カード選択
  def select_card(%{"user_id" => user_id} = params, socket) do
    ap = Map.get(params, "ap", nil)
    sp = Map.get(params, "sp", nil)
    card_id = Map.get(params, "card_id", nil)
    room_id = socket.assigns.user_assign.room_id

    Logger.info("#{user_id}, #{card_id}, #{ap}, #{sp}")

    # 従来のRedis処理（とりあえず残しておく）
    Redis.hset("room:#{room_id}:game:#{user_id}:status", "sp", sp)
    # TODO: APの値保存方法 要検討
    Enum.each(ap, fn x ->
      Redis.rpush("room:#{room_id}:game:#{user_id}:status:ap", x)
    end)

    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", card_id)
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")

    # GameServerにカード選択アクションを通知
    GameServer.player_action(room_id, user_id, :select_card, %{
      "card_id" => card_id,
      "sp" => sp,
      "ap" => ap
    })

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

    Redis.hset(
      "room:#{room_id}:game:#{user_id}:status:next_card",
      %{
        "set_pos" => set_pos,
        "card_id" => card_data[:card_id],
        "is_active" => card_data[:is_active],
        "is_close" => card_data[:is_close],
        "hp" => card_data[:hp],
        "level" => card_data[:level],
        "attack" => card_data[:attack],
        "speed" => card_data[:speed],
        "range" => card_data[:range]
      }
    )

    Logger.info("Card data set successfully")

    # プレイヤーを待機状態に遷移
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")
    # set_cardを初期化
    Redis.set("room:#{room_id}:game:#{user_id}:status:set_card", 0)

    # GameServerにカード配置アクションを通知
    GameServer.player_action(room_id, user_id, :set_position, %{
      "set_pos" => set_pos,
      "card_data" => card_data
    })

    {:noreply, socket}
  end

  def open_skill_end(%{"user_id" => user_id}, socket) do
    Logger.info("this user is #{user_id}")
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")

    # GameServerにスキル終了アクションを通知
    GameServer.player_action(room_id, user_id, :open_skill_end)

    {:noreply, socket}
  end

  def open_phase_end(%{"user_id" => user_id}, socket) do
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")

    # GameServerにオープンフェイズ終了アクションを通知
    GameServer.player_action(room_id, user_id, :open_phase_end)

    {:noreply, socket}
  end

  def action_card(%{"user_id" => user_id, "action_id" => action_id, "target" => target}, socket) do
    room_id = socket.assigns.user_assign.room_id
    Redis.set("room:#{room_id}:game:#{user_id}:is_wait", "true")

    # GameServerにカードアクションを通知(アクションIDとターゲットを渡す)
    GameServer.player_action(room_id, user_id, :action_select_end, %{
      "action_id" => action_id,
      "target" => target
    })

    {:noreply, socket}
  end
end

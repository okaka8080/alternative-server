defmodule AlternativeServerWeb.RoomChannel do
  use Phoenix.Channel
  alias AlternativeServer.Accounts
  alias AlternativeServer.Redis
  alias AlternativeServerWeb.RoomChannelGame
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
        # すでにメンバーに含まれていなければ追加する
        {:ok, members} = Redis.lrange("room:#{private_room_id}:members", 0, -1)

        unless user.id in members do
          Redis.lpush("room:#{private_room_id}:members", user.id)
        end

        send(self(), {:after_join, %{user_id: user.id, user_name: user.name}})
        {:ok, assign(socket, :user_assign, %{user: user, room_id: private_room_id})}

      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  # 認証処理
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
    Logger.info("message from: #{user_id}")
    Logger.info(socket.assigns.user_assign.room_id)
    room_id = socket.assigns.user_assign.room_id

    case RoomChannelGame.set_ready_logic(room_id, user_id, status) do
      {:ok, :both_ready} ->
        Logger.info("Both players are ready. Broadcasting duel_start.")
        broadcast!(socket, "duel_start", %{status: true})

      {:ok, :not_ready} ->
        Logger.info("One or both players are not ready.")
        broadcast!(socket, "duel_start", %{status: false})

      {:error, :members_not_found} ->
        Logger.error("Failed to fetch room members.")
        broadcast!(socket, "duel_start", %{status: false})
    end

    {:noreply, socket}
  end

  # デュエルセッション開始
  def handle_in("finish_ready", params, socket) do
    RoomChannelGame.finish_ready(params, socket)
  end

  # セットフェイズ：カード選択
  def handle_in("select_card", params, socket) do
    RoomChannelGame.select_card(params, socket)
  end

  # セットフェイズ：カード配置
  def handle_in("set_card", params, socket) do
    RoomChannelGame.set_card(params, socket)
  end

  def handle_in("open_skill_end", params, socket) do
    RoomChannelGame.open_skill_end(params, socket)
  end

  def handle_in("open_phase_end", params, socket) do
    RoomChannelGame.open_phase_end(params, socket)
  end

  # =============================================================================
  # 【削除】check_waitハンドラーは不要になりました
  #
  # 理由:
  # - GameServerが自動でブロードキャストするため、手動チェックが不要
  # - リアルタイムpush型に移行済み
  # - クライアントからのcheck_wait呼び出しも不要
  #
  # 従来: クライアント → check_wait → ポーリング → ブロードキャスト
  # 新仕様: プレイヤーアクション → GameServer → 自動ブロードキャスト
  # =============================================================================

  def handle_info({:after_join, user}, socket) do
    broadcast(socket, "user_joined", user)
    Logger.info("user is #{user.user_id}, #{user.user_name}")
    {:noreply, socket}
  end

  def terminate(_reason, socket) do
    broadcast!(socket, "user_left", %{user_id: socket.assigns.user_assign.user.id})
  end
end

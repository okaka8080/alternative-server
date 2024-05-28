defmodule AlternativeServerWeb.RoomChannel do
  use Phoenix.Channel
  alias AlternativeServer.Accounts
  alias AlternativeServer.Redis
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
        Redis.set("room_state_#{private_room_id}", "0")
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
      {:ok, nummber} = Redis.incr("room_state_#{socket.assigns.user_assign.room_id}")
      # {:ok, value} = Redis.get("room_state_#{socket.assigns.user_assign.room_id}")
      Logger.info("incr to #{nummber}")
    else
      Redis.decr("room_state_#{socket.assigns.user_assign.room_id}")
      # {:ok, value} = Redis.get("room_state_#{socket.assigns.user_assign.room_id}")
      # Logger.info("decr to #{value}")
    end

    case Redis.get("room_state_#{socket.assigns.user_assign.room_id}") do
      {:ok, room_state} when room_state == "2" ->
        Logger.info("room_state is 2")
        broadcast!(socket, "duel_start", %{status: true})
        {:noreply, socket}

      {:ok, room_state} when room_state != "2" ->
        Logger.info("room_state is not 2, it's #{room_state}")
        broadcast!(socket, "duel_start", %{status: false})
        {:noreply, socket}

      _ ->
        Logger.info("did not receive {:ok, room_state} tuple")
        broadcast!(socket, "duel_start", %{status: false})
        {:noreply, socket}
    end
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

defmodule AlternativeServerWeb.RoomChannel do
  use Phoenix.Channel
  alias AlternativeServer.Accounts
  require Logger

  def join("room:lobby", _message, socket) do
    {:ok, socket}
  end

  def join("room:" <> private_room_id, params, socket) do
    case authenticate(params) do
      {:ok, user} ->
        send(self(), {:after_join, %{user_id: user.user.id, user_name: user.user.name}})
        {:ok, assign(socket, :user, user)}
      _ ->
        {:error, %{reason: "unauthorized"}}
    end
  end

  def authenticate(params) do
    token = params["token"]
    Logger.info("token is #{token}")
    if user = Accounts.get_user_by_session_token(token |> Base.decode64!()) do
      Logger.info("joined user is #{user.name}")
      {:ok, %{user: user}}
    else
      Logger.error("joined user is not found")
      {:error, %{reason: "unauthorized"}}
    end
  end

  def handle_in("new_msg", %{"body" => body}, socket) do
    broadcast!(socket, "new_msg", %{body: body})
    {:noreply, socket}
  end

  def handle_in("stanby", payload, socket) do
    broadcast!(socket, "stanby", payload)
    {:noreply, socket}
  end

  def handle_info({:after_join, user}, socket) do
    broadcast(socket, "user_joined", user)
    Logger.info("user is #{user.user_id}, #{user.user_name}")
    {:noreply, socket}
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

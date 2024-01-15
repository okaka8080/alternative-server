defmodule AlternativeServerWeb.V1.UserApiSessionController do
  use AlternativeServerWeb, :controller

  alias AlternativeServer.Accounts

  def create(conn, %{"email" => email, "password" => password}) do
    if user = Accounts.get_user_by_email_and_password(email, password) do
      token = Accounts.generate_user_session_token(user) |> Base.encode64()
      json(conn, %{token: token})
    else
      conn
      |> put_status(:unauthorized)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"401")
    end
  end

  def register(conn, params) do
    if result = Accounts.register_user(params) do
      {:ok, user} = result
      token = Accounts.generate_user_session_token(user) |> Base.encode64()
      json(conn, %{id: user.id, name: user.name, email: user.email, coins: user.coins,token: token})
    else
      conn
      |> put_status(:bad_request)
      |> put_view(AlternativeServerWeb.ErrorHTML)
      |> render(:"400")
    end
  end

  @spec status(Plug.Conn.t(), any()) :: Plug.Conn.t()
  def status(conn, _params) do
    user = conn.assigns.current_user

    json(conn, %{
      status: user.email <> " enable"
    })
  end
end

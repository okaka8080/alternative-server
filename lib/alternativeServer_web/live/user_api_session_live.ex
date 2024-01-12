defmodule AlternativeServerWeb.UserApiSessionLive do
  use AlternativeServerWeb, :live_view

  def render("token.json", %{token: token}) do
    %{token: token}
  end

  def render("status.json", %{status: status}) do
    %{status: status}
  end
end

defmodule AlternativeServerWeb.V1.HealthCheckController do
  use AlternativeServerWeb, :controller

  def getHealth(conn, _params) do
    json(conn, %{message: "Health Check is OK!!"})
  end

  def postHealth(conn, params) do

    json(conn, params)
  end

end

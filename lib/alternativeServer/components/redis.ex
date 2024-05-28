defmodule AlternativeServer.Redis do
  require Logger

  @doc """
  Redis用関数
  """
  def conn() do
    {:ok, conn} = Redix.start_link(host: "redis", port: 6379)
    conn
  end

  def set(key, data) do
    conn = conn()
    Redix.command(conn, ["SET", key, data])
  end

  def get(key) do
    conn = conn()
    Redix.command(conn, ["GET", key])
  end

  def del(key) do
    conn = conn()
    Redix.command(conn, ["DEL", key])
  end

  def incr(key) do
    conn = conn()
    Redix.command(conn, ["INCR", key])
  end

  def decr(key) do
    conn = conn()
    Redix.command(conn, ["DECR", key])
  end
end

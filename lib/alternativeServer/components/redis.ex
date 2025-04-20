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

  def setnx(key, data) do
    conn = conn()
    Redix.command(conn, ["SETNX", key, data])
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

  def lpush(key, data) do
    conn = conn()
    Redix.command(conn, ["LPUSH", key, data])
  end

  def rpush(key, data) do
    conn = conn()
    Redix.command(conn, ["RPUSH", key, data])
  end

  def lpop(key) do
    conn = conn()
    Redix.command(conn, ["LPOP", key])
  end

  def lrange(key, start, limit) do
    conn = conn()
    Redix.command(conn, ["LRANGE", key, start, limit])
  end

  def hget(key, field) do
    conn = conn()
    Redix.command(conn, ["HGET", key, field])
  end

  def hgetall(key) do
    conn = conn()
    Redix.command(conn, ["HGETALL", key])
  end

  # 1フィールド用
  def hset(key, field, data) do
    conn = conn()
    case Redix.command(conn, ["HSET", key, field, data]) do
      {:ok, response} ->
        IO.puts("HSET successful: #{response}")
        {:ok, response}
      {:error, reason} ->
        IO.puts("HSET failed: #{reason}")
        {:error, reason}
    end
  end

  # 複数フィールド用
  def hset(key, map) when is_map(map) do
    conn = conn()
    kv_list = Enum.flat_map(map, fn {k, v} -> [to_string(k), to_string(v)] end)
    case Redix.command(conn, ["HSET", key | kv_list]) do
      {:ok, response} ->
        IO.puts("HSET successful: #{response}")
        {:ok, response}
      {:error, reason} ->
        IO.puts("HSET failed: #{reason}")
        {:error, reason}
    end
  end

  def hsetnx(key, field, data) do
    conn = conn()
    Redix.command(conn, ["HSETNX", key, field, data])
  end

  def hlen(key) do
    conn = conn()
    Redix.command(conn, ["HLEN", key])
  end

  def hreset(key) do
    conn = conn()
    case Redix.command(conn, ["DEL", key]) do
      {:ok, response} ->
        IO.puts("HRESET successful: #{response}")
        {:ok, response}
      {:error, reason} ->
        IO.puts("HRESET failed: #{reason}")
        {:error, reason}
    end
  end

end

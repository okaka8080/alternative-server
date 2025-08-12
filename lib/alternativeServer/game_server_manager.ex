defmodule AlternativeServer.GameServerManager do
  @moduledoc """
  GameServerプロセスの起動・停止・管理を行うモジュール
  """

  require Logger

  @doc """
  指定されたルームIDでGameServerを起動します
  """
  def start_game_server(room_id) do
    case game_server_running?(room_id) do
      true ->
        Logger.info("GameServer already running for room: #{room_id}")
        {:ok, :already_started}

      false ->
        # DynamicSupervisorを使ってGameServerを動的に起動
        child_spec = {AlternativeServer.Game.GameServer, {%{}, room_id}}

        case DynamicSupervisor.start_child(AlternativeServer.GameSupervisor, child_spec) do
          {:ok, pid} ->
            Logger.info("GameServer started successfully for room: #{room_id}, PID: #{inspect(pid)}")
            {:ok, pid}

          {:error, {:already_started, pid}} ->
            Logger.info("GameServer was already started for room: #{room_id}, PID: #{inspect(pid)}")
            {:ok, pid}

          {:error, reason} ->
            Logger.error("Failed to start GameServer for room: #{room_id}, reason: #{inspect(reason)}")
            {:error, reason}
        end
    end
  end

  @doc """
  指定されたルームIDのGameServerを停止します
  """
  def stop_game_server(room_id) do
    case Registry.lookup(AlternativeServer.GameRegistry, room_id) do
      [{pid, _}] ->
        Logger.info("Stopping GameServer for room: #{room_id}, PID: #{inspect(pid)}")
        DynamicSupervisor.terminate_child(AlternativeServer.GameSupervisor, pid)

      [] ->
        Logger.warning("GameServer not found for room: #{room_id}")
        {:error, :not_found}
    end
  end

  @doc """
  指定されたルームIDのGameServerが起動しているかチェックします
  """
  def game_server_running?(room_id) do
    case Registry.lookup(AlternativeServer.GameRegistry, room_id) do
      [{_pid, _}] -> true
      [] -> false
    end
  end

  @doc """
  現在起動中の全GameServerのルームIDリストを取得します
  """
  def list_active_rooms do
    Registry.select(AlternativeServer.GameRegistry, [{{:"$1", :"$2", :"$3"}, [], [:"$1"]}])
  end

  @doc """
  GameServerの詳細情報を取得します
  """
  def get_game_server_info(room_id) do
    case Registry.lookup(AlternativeServer.GameRegistry, room_id) do
      [{pid, _}] ->
        {:ok, %{
          room_id: room_id,
          pid: pid,
          status: :running
        }}

      [] ->
        {:error, :not_found}
    end
  end

  @doc """
  全GameServerを停止します（メンテナンス時などに使用）
  """
  def stop_all_game_servers do
    active_rooms = list_active_rooms()
    Logger.info("Stopping #{length(active_rooms)} GameServers...")

    Enum.each(active_rooms, fn room_id ->
      stop_game_server(room_id)
    end)

    {:ok, length(active_rooms)}
  end
end

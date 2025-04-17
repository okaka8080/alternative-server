defmodule AlternativeServer.DuelSystem do
  alias AlternativeServer.Redis
  require Logger

  def main_routine() do

  end

  @doc """
  turn_id
  0: セットフェイズ
  1: オープンフェイズ
  2: アクションフェイズ
  """

  def change_turn(room_id) do
    Redis.incr("room:#{room_id}:game:currentTurn")
    Redis.set("room:#{room_id}:game:currentPhase", 0)
    Redis.set("room:#{room_id}:game:phaseState", 0)
  end

  def change_phase(turn_id) do
    case turn_id do
      0 ->
        Logger.info("turn to OpenPhase")
        1
      1 ->
        Logger.info("turn to ActionPhase")
        2
      2 ->
        Logger.info("turn to SetPhase")
        0
    end
  end

  def set_phase_routin() do
    # セットフェイズの開始を送る
    # 前のターンで選んだカードがあれば配置

    # 復活選択(クローズカードがあれば)

    # 使用するカードを選択、上昇させた属性値を送る

  end

  def check_set_card() do
    case Redis.get("set_card") do
      {:ok, value}
        -> Logger.info("set_card is #{value}")
      _
        -> Logger.info("set_card is not founded")
    end
  end

  def check_closed_card do
    case Redis.get("closed_card") do
      {:ok, value}
        -> Logger.info("set_card is #{value}")
      _
        -> Logger.info("set_card is not founded")
    end
  end

end

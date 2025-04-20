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
    # ターン数を取得
    {:ok, turn} = Redis.hget("room:#{room_id}:game:state", "turn")
    turnCount = String.to_integer(turn)
    # ターン数をインクリメント
    Redis.hset("room:#{room_id}:game:state", "turn", turnCount + 1)
    # フェイズをリセット
    Redis.hset("room:#{room_id}:game:state", "phase", 0)
    Redis.hset("room:#{room_id}:game:state", "phaseState", 0)
  end

  def hset_newCard(room_id, player_id, card_data) do
    position = card_data["set_pos"]
    Redis.hset(
    "room:#{room_id}:game:#{player_id}:field:#{position}",
    %{
      "card_id" => card_data["card_id"],
      "is_active" => card_data["is_active"],
      "is_close" => card_data["is_close"]
      # TODO: 他のカードデータも後ほど追加
    }
  )
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
      {:ok, value} ->
        Logger.info("set_card is #{value}")

      _ ->
        Logger.info("set_card is not founded")
    end
  end

  def check_closed_card do
    case Redis.get("closed_card") do
      {:ok, value} ->
        Logger.info("set_card is #{value}")

      _ ->
        Logger.info("set_card is not founded")
    end
  end
end

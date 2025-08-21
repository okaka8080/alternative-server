defmodule AlternativeServer.GameServerTest do
  @moduledoc """
  GameServerの基本動作をテストするスクリプト
  """

  alias AlternativeServer.GameServerManager
  alias AlternativeServer.Game.GameServer
  require Logger

  def run_basic_test do
    IO.puts("GameServer基本動作テスト開始")
    room_id = "test_room_#{:rand.uniform(1000)}"

    # 1. GameServer起動テスト
    IO.puts("1️⃣ GameServer起動テスト...")
    case GameServerManager.start_game_server(room_id) do
      {:ok, _pid} ->
        IO.puts("✅ GameServer起動成功: #{room_id}")
      {:error, reason} ->
        IO.puts("❌ GameServer起動失敗: #{inspect(reason)}")
        {:error, reason}
    end

    # 2. プレイヤー追加テスト
    IO.puts("2️⃣ プレイヤー追加テスト...")
    GameServer.add_player(room_id, "player1")
    GameServer.add_player(room_id, "player2")
    IO.puts("✅ プレイヤー追加完了")

    # 3. プレイヤーアクションテスト
    IO.puts("3️⃣ プレイヤーアクションテスト...")
    GameServer.player_action(room_id, "player1", :ready)
    Process.sleep(100) # ちょっと待つ
    GameServer.player_action(room_id, "player2", :ready)
    Process.sleep(100) # ちょっと待つ
    IO.puts("✅ ready アクション完了")

    # 4. カード選択アクションテスト
    IO.puts("4️⃣ カード選択アクションテスト...")
    GameServer.player_action(room_id, "player1", :select_card, %{
      "card_id" => "card_001",
      "sp" => 5,
      "ap" => [1, 2, 3]
    })
    Process.sleep(100)
    GameServer.player_action(room_id, "player2", :select_card, %{
      "card_id" => "card_002",
      "sp" => 4,
      "ap" => [2, 3, 4]
    })
    Process.sleep(100)
    IO.puts("✅ カード選択アクション完了")

    # 5. GameServer停止テスト
    IO.puts("5️⃣ GameServer停止テスト...")
    case GameServerManager.stop_game_server(room_id) do
      :ok ->
        IO.puts("✅ GameServer停止成功")
      {:error, reason} ->
        IO.puts("❌ GameServer停止失敗: #{inspect(reason)}")
    end

    IO.puts("🎉 テスト完了!")
    :ok
  end

  def check_active_servers do
    active_rooms = GameServerManager.list_active_rooms()
    IO.puts("🔍 現在アクティブなGameServer: #{inspect(active_rooms)}")
    active_rooms
  end

  def run_turn_management_test do
    IO.puts("🎮 Turn Management Test 開始!")
    room_id = "turn_test_room_#{:rand.uniform(1000)}"

    # GameServer起動
    case GameServerManager.start_game_server(room_id) do
      {:ok, _pid} ->
        IO.puts("✅ GameServer起動成功: #{room_id}")
      {:error, reason} ->
        IO.puts("❌ GameServer起動失敗: #{inspect(reason)}")
        {:error, reason}
    end

    # プレイヤー追加
    GameServer.add_player(room_id, "player1")
    GameServer.add_player(room_id, "player2")

    # 初期状態確認
    state = GameServer.get_game_state(room_id)
    IO.puts("📊 初期状態: Phase=#{state.phase}, Turn=#{state.turn}, Players=#{map_size(state.players)}")

    # ターン1のテスト
    IO.puts("\n🎯 ターン1テスト開始...")
    execute_turn_sequence(room_id, 1)

    state = GameServer.get_game_state(room_id)
    IO.puts("📊 ターン1後: Phase=#{state.phase}, Turn=#{state.turn}")

    # ターン2のテスト（アクションフェイズまで）
    IO.puts("\n🎯 ターン2テスト開始...")
    execute_turn_sequence(room_id, 2)

    state = GameServer.get_game_state(room_id)
    IO.puts("📊 ターン2後: Phase=#{state.phase}, Turn=#{state.turn}")

    # アクションフェイズのテスト
    IO.puts("\n🎯 アクションフェイズテスト...")
    GameServer.player_action(room_id, "player1", :action_phase_end, %{})
    GameServer.player_action(room_id, "player2", :action_phase_end, %{})

    state = GameServer.get_game_state(room_id)
    IO.puts("📊 アクションフェイズ後: Phase=#{state.phase}, Turn=#{state.turn}")

    # クリーンアップ
    GameServerManager.stop_game_server(room_id)
    IO.puts("🎉 Turn Management Test 完了!")
    :ok
  end

  def run_long_game_test do
    IO.puts("🎮 Long Game Test (ゲーム終了条件まで) 開始!")
    room_id = "long_game_test_#{:rand.uniform(1000)}"

    # GameServer起動
    {:ok, _pid} = GameServerManager.start_game_server(room_id)
    GameServer.add_player(room_id, "player1")
    GameServer.add_player(room_id, "player2")

    # 12ターンまで実行してゲーム終了をテスト
    result = Enum.reduce_while(1..12, :continue, fn turn, _acc ->
      IO.puts("\n🎯 ターン#{turn}実行中...")

      state_before = GameServer.get_game_state(room_id)
      if state_before.phase == :game_ended do
        IO.puts("🏁 ゲーム終了を検知! 最終ターン: #{state_before.turn}")
        {:halt, :game_ended}
      else
        execute_turn_sequence(room_id, turn)

        # ターン2以降はアクションフェイズも実行
        if turn > 1 do
          state = GameServer.get_game_state(room_id)
          if state.phase == :action_phase_check do
            GameServer.player_action(room_id, "player1", :action_phase_end, %{})
            GameServer.player_action(room_id, "player2", :action_phase_end, %{})
          end
        end

        state_after = GameServer.get_game_state(room_id)
        IO.puts("📊 ターン#{turn}完了: Phase=#{state_after.phase}, Turn=#{state_after.turn}")

        if state_after.phase == :game_ended do
          IO.puts("🏁 ゲーム終了! 最終ターン: #{state_after.turn}")
          {:halt, :game_ended}
        else
          {:cont, :continue}
        end
      end
    end)

    GameServerManager.stop_game_server(room_id)
    IO.puts("🎉 Long Game Test 完了! 結果: #{inspect(result)}")
    :ok
  end

  # ターンの基本シーケンスを実行するヘルパー関数
  defp execute_turn_sequence(room_id, turn) do
    # Ready
    GameServer.player_action(room_id, "player1", :finish_ready, %{})
    GameServer.player_action(room_id, "player2", :finish_ready, %{})
    Process.sleep(50)

    # Card Select
    GameServer.player_action(room_id, "player1", :select_card, %{
      "card_id" => "card_#{turn}_1", "sp" => 100 + turn, "ap" => 50 + turn
    })
    GameServer.player_action(room_id, "player2", :select_card, %{
      "card_id" => "card_#{turn}_2", "sp" => 120 + turn, "ap" => 60 + turn
    })
    Process.sleep(50)

    # Position
    GameServer.player_action(room_id, "player1", :set_position, %{
      "set_pos" => [turn, turn + 1], "card_data" => %{}
    })
    GameServer.player_action(room_id, "player2", :set_position, %{
      "set_pos" => [turn + 2, turn + 3], "card_data" => %{}
    })
    Process.sleep(50)

    # Open Skill
    GameServer.player_action(room_id, "player1", :open_skill_end, %{})
    GameServer.player_action(room_id, "player2", :open_skill_end, %{})
    Process.sleep(50)

    # Open Phase End
    GameServer.player_action(room_id, "player1", :open_phase_end, %{})
    GameServer.player_action(room_id, "player2", :open_phase_end, %{})
    Process.sleep(50)
  end

  def run_summon_test do
  IO.puts("🎴 Summon Cards Test 開始!")
  room_id = "summon_test_#{:rand.uniform(1000)}"

  # GameServer起動
  {:ok, _pid} = GameServerManager.start_game_server(room_id)
  GameServer.add_player(room_id, "player1")
  GameServer.add_player(room_id, "player2")

  # 初期状態でターン2に進める（召喚テスト用）
  IO.puts("🎯 ターン1を完了してターン2へ...")
  execute_turn_sequence(room_id, 1)

  # ターン2: カードを配置する
  IO.puts("🎯 ターン2でカードを配置...")
  GameServer.player_action(room_id, "player1", :ready, %{})
  GameServer.player_action(room_id, "player2", :ready, %{})
  Process.sleep(50)

  # カード配置（setステータスで配置）
  card_data_1 = %{
    "card_id" => "summon_test_card_1",
    "hp" => 150,
    "name" => "Test Summon Card 1",
    "attack" => 80,
    "guard" => 20,
    "speed" => 2,
    "range" => 1
  }

  card_data_2 = %{
    "card_id" => "summon_test_card_2",
    "hp" => 120,
    "name" => "Test Summon Card 2",
    "attack" => 60,
    "guard" => 30,
    "speed" => 3,
    "range" => 2
  }

  GameServer.player_action(room_id, "player1", :set_position, %{
    "set_pos" => 5,
    "card_data" => card_data_1
  })
  GameServer.player_action(room_id, "player2", :set_position, %{
    "set_pos" => 3,
    "card_data" => card_data_2
  })
  Process.sleep(100)

  # 配置後の状態確認
  state_after_set = GameServer.get_game_state(room_id)
  IO.puts("📊 カード配置後の状態確認...")
  player1_field = Map.get(state_after_set.fields, "player1")
  player2_field = Map.get(state_after_set.fields, "player2")

  card_1_status = get_in(player1_field, [5, :status])
  card_2_status = get_in(player2_field, [3, :status])

  IO.puts("✅ Player1のカード(位置5)ステータス: #{card_1_status}")
  IO.puts("✅ Player2のカード(位置3)ステータス: #{card_2_status}")

  # 召喚フェーズに進める（カード選択で召喚が発動）
  IO.puts("🎯 召喚フェーズへ...")
  GameServer.player_action(room_id, "player1", :select_card, %{
    "card_id" => "trigger_summon_1", "sp" => 200, "ap" => 100
  })
  GameServer.player_action(room_id, "player2", :select_card, %{
    "card_id" => "trigger_summon_2", "sp" => 180, "ap" => 90
  })
  Process.sleep(200) # 召喚処理のための待機時間を延長

  # 召喚後の状態確認
  state_after_summon = GameServer.get_game_state(room_id)
  IO.puts("📊 召喚後の状態確認...")

  player1_field_after = Map.get(state_after_summon.fields, "player1")
  player2_field_after = Map.get(state_after_summon.fields, "player2")

  card_1_status_after = get_in(player1_field_after, [5, :status])
  card_2_status_after = get_in(player2_field_after, [3, :status])

  IO.puts("✅ 召喚後 Player1のカード(位置5)ステータス: #{card_1_status_after}")
  IO.puts("✅ 召喚後 Player2のカード(位置3)ステータス: #{card_2_status_after}")

  # 検証結果
  summon_success = card_1_status_after == "active" && card_2_status_after == "active"

  if summon_success do
    IO.puts("🎉 召喚テスト成功！ カードが正しく 'set' → 'active' に変更されました✨")
  else
    IO.puts("❌ 召喚テスト失敗💦 カードステータスが期待通りに変更されませんでした")
  end

  # クリーンアップ
  GameServerManager.stop_game_server(room_id)
  IO.puts("🎉 Summon Cards Test 完了!")

  %{
    success: summon_success,
    before_summon: %{card_1: card_1_status, card_2: card_2_status},
    after_summon: %{card_1: card_1_status_after, card_2: card_2_status_after}
  }
end

def run_summon_payload_test do
  IO.puts("📦 Summon Payload Test 開始!")
  room_id = "payload_test_#{:rand.uniform(1000)}"

  try do
    # GameServer起動とセットアップ
    {:ok, _pid} = GameServerManager.start_game_server(room_id)
    GameServer.add_player(room_id, "player1")
    GameServer.add_player(room_id, "player2")

    # ターン1完了
    execute_turn_sequence(room_id, 1)

    # ターン2でカード配置
    GameServer.player_action(room_id, "player1", :ready, %{})
    GameServer.player_action(room_id, "player2", :ready, %{})
    Process.sleep(50)

    # テスト用のカードデータ
    test_card_data = %{
      "card_id" => "payload_test_card_123",
      "hp" => 200,
      "name" => "Payload Test Card",
      "attack" => 100,
      "guard" => 50,
      "speed" => 4,
      "range" => 3
    }

    GameServer.player_action(room_id, "player1", :set_position, %{
      "set_pos" => 7,
      "card_data" => test_card_data
    })
    GameServer.player_action(room_id, "player2", :set_position, %{
      "set_pos" => 2,
      "card_data" => %{"card_id" => "dummy_card", "hp" => 50}
    })
    Process.sleep(100)

    # 召喚トリガー（ブロードキャストをキャッチするための準備）
    IO.puts("🎯 召喚ペイロードの検証を開始...")

    # Phoenix.PubSubを使ってブロードキャストをキャッチ
    Phoenix.PubSub.subscribe(AlternativeServer.PubSub, "room:" <> room_id)

    # 召喚を実行
    GameServer.player_action(room_id, "player1", :select_card, %{
      "card_id" => "summon_trigger", "sp" => 250, "ap" => 120
    })
    GameServer.player_action(room_id, "player2", :select_card, %{
      "card_id" => "summon_trigger_2", "sp" => 230, "ap" => 110
    })

    # ブロードキャストメッセージを待つ
    summon_event = receive do
      %Phoenix.Socket.Broadcast{event: "event", payload: %{events: events}} ->
        # summonイベントを探す
        Enum.find(events, fn event ->
          Map.get(event, :event_type) == "summon"
        end)
      _ -> nil
    after
      1000 -> nil
    end

    # ペイロード検証
    if summon_event do
      payload = Map.get(summon_event, :payload)
      IO.puts("✅ 召喚ペイロード受信成功！")
      IO.puts("📦 ペイロード内容: #{inspect(payload)}")

      # ペイロードの構造チェック
      has_user_id = Map.has_key?(payload, :user_id)
      has_position = Map.has_key?(payload, :position)
      has_card_id = Map.has_key?(payload, :card_id)
      has_turn = Map.has_key?(payload, :turn)

      payload_valid = has_user_id && has_position && has_card_id && has_turn

      if payload_valid do
        IO.puts("🎉 ペイロード構造テスト成功！ 全ての必要フィールドが含まれています✨")
      else
        IO.puts("❌ ペイロード構造テスト失敗💦 必要フィールドが不足しています")
      end

      %{
        success: payload_valid,
        payload: payload,
        fields: %{user_id: has_user_id, position: has_position, card_id: has_card_id, turn: has_turn}
      }
    else
      IO.puts("❌ 召喚ペイロード受信失敗💦 ブロードキャストが届きませんでした")
      %{success: false, payload: nil}
    end
  rescue
    error ->
      IO.puts("❌ テスト中にエラーが発生しました: #{inspect(error)}")
      %{success: false, payload: nil, error: error}
  after
    # クリーンアップ処理（必ず実行される）
    GameServerManager.stop_game_server(room_id)
    IO.puts("🎉 Summon Payload Test 完了!")
  end
end

def run_field_status_transition_test do
  IO.puts("🔄 Field Status Transition Test 開始!")
  room_id = "transition_test_#{:rand.uniform(1000)}"

  {:ok, _pid} = GameServerManager.start_game_server(room_id)
  GameServer.add_player(room_id, "player1")
  GameServer.add_player(room_id, "player2")

  # ターン1完了
  execute_turn_sequence(room_id, 1)

  # 複数のカードを配置してステータス変化をテスト
  GameServer.player_action(room_id, "player1", :ready, %{})
  GameServer.player_action(room_id, "player2", :ready, %{})
  Process.sleep(50)

  # Player1に複数カード配置
  GameServer.player_action(room_id, "player1", :set_position, %{
    "set_pos" => 1,
    "card_data" => %{"card_id" => "multi_test_1", "hp" => 100}
  })
  Process.sleep(50)

  GameServer.player_action(room_id, "player1", :set_position, %{
    "set_pos" => 9,
    "card_data" => %{"card_id" => "multi_test_2", "hp" => 80}
  })
  Process.sleep(50)

  # Player2にも配置
  GameServer.player_action(room_id, "player2", :set_position, %{
    "set_pos" => 5,
    "card_data" => %{"card_id" => "multi_test_3", "hp" => 120}
  })
  Process.sleep(100)

  # 配置後の全フィールド状態確認
  state_before = GameServer.get_game_state(room_id)
  IO.puts("📊 配置後のフィールド状態:")
  print_field_status(state_before.fields)

  # 召喚実行
  GameServer.player_action(room_id, "player1", :select_card, %{
    "card_id" => "multi_summon", "sp" => 300, "ap" => 150
  })
  GameServer.player_action(room_id, "player2", :select_card, %{
    "card_id" => "multi_summon_2", "sp" => 280, "ap" => 140
  })
  Process.sleep(200)

  # 召喚後の全フィールド状態確認
  state_after = GameServer.get_game_state(room_id)
  IO.puts("📊 召喚後のフィールド状態:")
  print_field_status(state_after.fields)

  # 変化の検証
  transitions = analyze_status_transitions(state_before.fields, state_after.fields)

  IO.puts("🔄 ステータス変化:")
  Enum.each(transitions, fn {player_id, position, before, after_status} ->
    IO.puts("  #{player_id} 位置#{position}: #{before} → #{after_status}")
  end)

  success = Enum.all?(transitions, fn {_, _, before, after_status} ->
    before == "set" && after_status == "active"
  end)

  if success && length(transitions) > 0 do
    IO.puts("🎉 フィールドステータス変化テスト成功！ 全てのsetカードがactiveになりました✨")
  else
    IO.puts("❌ フィールドステータス変化テスト失敗💦")
  end

  GameServerManager.stop_game_server(room_id)
  IO.puts("🎉 Field Status Transition Test 完了!")

  %{success: success, transitions: transitions}
end

# フィールドの状態を見やすく表示するヘルパー
defp print_field_status(fields) do
  Enum.each(fields, fn {player_id, field} ->
    IO.puts("  #{player_id}:")
    Enum.each(field, fn {position, card_data} ->
      if card_data do
        status = Map.get(card_data, :status, "unknown")
        card_id = Map.get(card_data, :card_id, "unknown")
        IO.puts("    位置#{position}: #{card_id} (#{status})")
      end
    end)
  end)
end

# ステータス変化を分析するヘルパー
defp analyze_status_transitions(fields_before, fields_after) do
  for {player_id, field_before} <- fields_before,
      {position, card_before} <- field_before,
      card_before != nil,
      into: [] do
    field_after = Map.get(fields_after, player_id, %{})
    card_after = Map.get(field_after, position)

    status_before = Map.get(card_before, :status, "unknown")
    status_after = if card_after, do: Map.get(card_after, :status, "unknown"), else: "nil"

    if status_before != status_after do
      {player_id, position, status_before, status_after}
    else
      nil
    end
  end
  |> Enum.filter(& &1)
end
end

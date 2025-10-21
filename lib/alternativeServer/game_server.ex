defmodule AlternativeServer.Game.GameServer do
  use GenServer
  require Logger

  # このGenServerが持つ状態(State)を定義
  @enforce_keys [:room_id]
  defstruct room_id: nil,
            # ゲームの現在のフェーズ
            phase: :waiting_for_players,
            # 現在のターン数
            turn: 1,
            # %{player_id => %{ready: false, card: nil, ...}}
            players: %{},
            # %{player_id => %{1 => %{card_id: 1, hp: 100, name: "card_name", attack: 50, guard: 0, speed: 1, range: 1, status: "active"}, 2 => nil, 3 => nil...}}
            fields: %{},
            # アクションフェーズの行動順キュー
            action_queue: []

  @max_turns 100
  # 最大ターン数。ゲームバランスのためデフォルトは100ですが、configファイルで変更可能です。

  # ====================
  # クライアントAPI (Channelから呼び出す)
  # ====================

  def start_link({_opts, room_id}) do
    GenServer.start_link(__MODULE__, room_id, name: via_tuple(room_id))
  end

  # プレイヤー参加
  def add_player(room_id, user_id) do
    GenServer.cast(via_tuple(room_id), {:add_player, user_id})
  end

  # プレイヤーのアクション通知 (以前のnotify_player_readyなどもこれに統合)
  def player_action(room_id, user_id, action, data \\ %{}) do
    GenServer.cast(via_tuple(room_id), {:player_action, user_id, action, data})
  end

  # ゲームの状態を取得（デバッグ用）
  def get_game_state(room_id) do
    GenServer.call(via_tuple(room_id), :get_state)
  end

  def stop(room_id) do
    GenServer.stop(via_tuple(room_id))
  end

  # ====================
  # GenServer実装 (内部の動き)
  # ====================

  @impl true
  def init(room_id) do
    Logger.info("GameServer started for room: #{room_id}")
    # ゲーム開始時にRedisから初期データを読み込むのはここ
    initial_state = %__MODULE__{
      room_id: room_id,
      phase: :waiting_for_players,
      # 最初は空
      players: %{},
      # 最初は空
      fields: %{}
    }

    {:ok, initial_state}
  end

  # プレイヤー参加時の処理
  @impl true
  def handle_cast({:add_player, user_id}, state) do
    Logger.info("[#{state.room_id}] Player #{user_id} joined.")
    # Stateにプレイヤーを追加
    new_players = Map.put(state.players, user_id, %{ready: false})
    new_state = %{state | players: new_players}

    # Fieldsにもプレイヤーを追加
    new_fields =
      Map.put(new_state.fields, user_id, %{
        1 => nil,
        2 => nil,
        3 => nil,
        4 => nil,
        5 => nil,
        6 => nil,
        7 => nil,
        8 => nil,
        9 => nil
      })

    new_state = %{new_state | fields: new_fields}

    # 2人揃ったらゲーム開始を通知
    if map_size(new_state.players) == 2 do
      broadcast(new_state.room_id, "game_ready", %{message: "両プレイヤーが揃いました。"})
      # フェーズを準備完了待ちに移行
      {:noreply, %{new_state | phase: :ready_check}}
    else
      {:noreply, new_state}
    end
  end

  # プレイヤーのアクション処理 (メインロジック)
  @impl true
  def handle_cast({:player_action, user_id, action, data}, state) do
    Logger.info("[#{state.room_id}] Player #{user_id} action: #{action}")

    # 1. アクションに応じてStateを更新
    updated_state = update_state_for_action(state, user_id, action, data)

    # 2. 条件をチェックして、満たされていればブロードキャスト
    check_and_broadcast(updated_state)
  end

  # ゲーム状態の取得
  @impl true
  def handle_call(:get_state, _from, state) do
    {:reply, state, state}
  end

  # ====================
  # プライベート関数 (ロジックの詳細)
  # ====================

  # アクションに応じてStateを更新する
  defp update_state_for_action(state, user_id, :ready, _data) do
    # playersの中の特定のプレイヤーのreadyをtrueにする
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
    %{state | players: new_players}
  end

  defp update_state_for_action(state, user_id, :select_card, %{
         "card_id" => card_id,
         "sp" => sp,
         "ap" => ap
       }) do
    # プレイヤーのカード選択情報を更新
    new_players =
      Map.update!(state.players, user_id, fn p ->
        p
        |> Map.put(:ready, true)
        |> Map.put(:card_id, card_id)
        |> Map.put(:sp, sp)
        |> Map.put(:ap, ap)
      end)

    %{state | players: new_players}
  end

  defp update_state_for_action(state, user_id, :set_position, %{
         "set_pos" => set_pos,
         "card_data" => card_data
       }) do
    # 受け取ったデータをログ出力
    Logger.info("[#{state.room_id}] Player #{user_id} set_position - set_pos: #{set_pos}")

    Logger.info(
      "[#{state.room_id}] Player #{user_id} set_position - card_data: #{inspect(card_data)}"
    )

    # プレイヤーのカード配置情報を更新
    new_players =
      Map.update!(state.players, user_id, fn p ->
        p
        |> Map.put(:ready, true)
        |> Map.put(:set_pos, set_pos)
        |> Map.put(:card_data, card_data)
      end)

    # card_idの取得状況もログ出力
    card_id_atom = card_data[:card_id]
    card_id_string = card_data["card_id"]
    final_card_id = card_id_atom || card_id_string

    Logger.info(
      "[#{state.room_id}] card_id extraction - atom: #{inspect(card_id_atom)}, string: #{inspect(card_id_string)}, final: #{inspect(final_card_id)}"
    )

    # Fieldsにも配置情報を更新 - Channel側から送られてきた実際の値を使用
    new_fields =
      Map.update!(state.fields, user_id, fn field ->
        Map.put(field, set_pos, %{
          card_id: card_data[:card_id] || card_data["card_id"],
          hp: card_data[:hp] || card_data["hp"] || 100,
          name: card_data[:name] || card_data["name"] || "Unknown Card",
          attack: card_data[:attack] || card_data["attack"] || 0,
          guard: card_data[:guard] || card_data["guard"] || 0,
          speed: card_data[:speed] || card_data["speed"] || 1,
          range: card_data[:range] || card_data["range"] || 1,
          level: card_data[:level] || card_data["level"] || 1,
          is_active: card_data[:is_active] || card_data["is_active"] || false,
          is_close: card_data[:is_close] || card_data["is_close"] || false,
          status: "set"
        })
      end)

    Logger.info(
      "[#{state.room_id}] Updated field for player #{user_id}, position #{set_pos}: #{inspect(get_in(new_fields, [user_id, set_pos]))}"
    )

    %{state | players: new_players, fields: new_fields}
  end

  defp update_state_for_action(state, user_id, :open_skill_end, _data) do
    # プレイヤーのスキル終了状態を更新
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
    %{state | players: new_players}
  end

  defp update_state_for_action(state, user_id, :open_phase_end, _data) do
    # プレイヤーのオープンフェイズ終了状態を更新
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
    %{state | players: new_players}
  end

  defp update_state_for_action(state, user_id, :revival_select, data) do
    # プレイヤーの復活選択状態を更新
    new_players =
      Map.update!(state.players, user_id, fn p ->
        p
        |> Map.put(:ready, true)
        |> Map.put(:revival_data, data)
      end)

    %{state | players: new_players}
  end

  defp update_state_for_action(state, user_id, :action_phase_end, _data) do
    # プレイヤーのアクションフェイズ終了状態を更新
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
    %{state | players: new_players}
  end

  # アクションカード
  defp update_state_for_action(state, user_id, :action_card, %{"action" => action} = data) do
    # カードアクションの種類に応じて処理を分岐
    case action do
      "attack" ->
        handle_attack_action(state, user_id, data)

      "skill" ->
        handle_skill_action(state, user_id, data)

      "move" ->
        handle_move_action(state, user_id, data)

      "wait" ->
        handle_wait_action(state, user_id)

      "end_turn" ->
        # プレイヤーのアクション終了状態を更新
        new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
        %{state | players: new_players}

      _ ->
        Logger.warning(
          "[#{state.room_id}] Unknown action type: #{action} from player: #{user_id}"
        )

        state
    end
  end

  # 未知のアクションの場合はログを出して状態を変更しない
  defp update_state_for_action(state, user_id, action, data) do
    Logger.warning(
      "[#{state.room_id}] Unknown action: #{action} from player: #{user_id}, data: #{inspect(data)}"
    )

    state
  end

  # 攻撃アクションの処理
  defp handle_attack_action(
       state,
       user_id,
       %{"target_pos" => target_pos, "attacker_pos" => attacker_pos, "target_player_id" => target_player_id} = _data
     ) do
    Logger.info(
      "[#{state.room_id}] Player #{user_id} attacks player #{target_player_id}'s position #{target_pos} with card at #{attacker_pos}"
    )

    # 攻撃側のカード情報を取得
    attacker_card = get_in(state.fields, [user_id, attacker_pos])

    # 被攻撃側のカード情報を取得（相手プレイヤーから）
    target_card = get_in(state.fields, [target_player_id, target_pos])

    # ダメージ計算（ガード値も考慮）
    base_damage = if attacker_card, do: attacker_card.attack, else: 0
    guard_value = if target_card, do: target_card.guard, else: 0
    actual_damage = max(base_damage - guard_value, 0)
    new_target_hp = if target_card, do: max(target_card.hp - actual_damage, 0), else: 0

    Logger.info(
      "[#{state.room_id}] Base damage: #{base_damage}, Guard: #{guard_value}, Actual damage: #{actual_damage}, Target new HP: #{new_target_hp}"
    )

    # 相手プレイヤーのフィールドを更新
    new_fields =
      Map.update!(state.fields, target_player_id, fn field ->
        Map.update!(field, target_pos, fn card ->
          if card do
            updated_card = Map.put(card, :hp, new_target_hp)
            # HPが0になったら状態を"closed"に変更
            if new_target_hp <= 0 do
              Map.put(updated_card, :status, "closed")
            else
              updated_card
            end
          else
            nil
          end
        end)
      end)

    # プレイヤーのアクション完了状態を更新
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))

    # 更新されたstateを返す
    %{state | fields: new_fields, players: new_players}
  end

  # スキルアクションの処理
  # NOTE: 仮実装
  defp handle_skill_action(
         state,
         user_id,
         %{"skill_id" => skill_id, "caster_pos" => caster_pos} = _data
       ) do
    Logger.info(
      "[#{state.room_id}] Player #{user_id} uses skill #{skill_id} with card at #{caster_pos}"
    )

    # スキル効果をフィールドに適用
    # new_fields = apply_skill_effect(state.fields, user_id, caster_pos, skill_id)
    new_fields = state.fields # 仮実装
    %{state | fields: new_fields}
  end

  # 移動アクションの処理
  # NOTE: 仮実装
  defp handle_move_action(state, user_id, %{"from_pos" => from_pos, "to_pos" => to_pos} = _data) do
    Logger.info("[#{state.room_id}] Player #{user_id} moves card from #{from_pos} to #{to_pos}")

    # カードの位置を移動
    # new_fields = move_card_on_field(state.fields, user_id, from_pos, to_pos)
    new_fields = state.fields # 仮実装

    %{state | fields: new_fields}
  end

  # NOTE: 仮実装
  defp handle_wait_action(state, user_id) do
    Logger.info("[#{state.room_id}] Player #{user_id} chooses to wait")

    # プレイヤーの待機状態を更新
    new_players = Map.update!(state.players, user_id, &Map.put(&1, :ready, true))
    %{state | players: new_players}
  end

  # 条件をチェックして、満たされていればブロードキャストする
  defp check_and_broadcast(state) do
    case state.phase do
      # プレイヤー待ちフェーズ（新規追加）
      :waiting_for_players ->
        # このフェーズではプレイヤーの参加を待つだけ
        # 2人揃ったら add_player の処理で :ready_check に移行するので
        # ここでは特に何もしない
        {:noreply, state}

      # 現在のフェーズが「準備完了待ち」の場合
      :ready_check ->
        if all_players_ready?(state) do
          Logger.info(
            "[#{state.room_id}] All players ready, transitioning to card select phase (Turn #{state.turn})"
          )

          new_state = reset_ready_status(state)
          # ターン1の場合はカード選択フェーズへ
          # ターン2以降は配置フェーズへ
          if state.turn == 1 do
            broadcast(state.room_id, "turn_changed:first", %{status: true, turn: state.turn})
            {:noreply, %{new_state | phase: :card_select_check}}
          else
            broadcast(state.room_id, "turn_changed:main", %{status: true, turn: state.turn})
            {:noreply, %{new_state | phase: :position_check}}
          end
        else
          {:noreply, state}
        end

      # 現在のフェーズが「カード選択待ち」の場合
      :card_select_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] All players selected cards")

          # プレイヤーデータを整形してブロードキャスト
          [player1_id, player2_id] = Map.keys(state.players)
          player1_data = Map.get(state.players, player1_id)
          player2_data = Map.get(state.players, player2_id)

          # 2ターン目以降は召喚カードを調べる
          updated_state =
            if state.turn > 1 do
              Logger.info("[#{state.room_id}] Turn #{state.turn} - Summoning cards for players")
              # 召喚処理でステータスも更新されたstateを受け取る
              summon_set_cards(state)
            else
              state
            end

          broadcast_data = %{
            status: true,
            user1: %{
              user_id: player1_id,
              card_id: player1_data.card_id,
              sp: player1_data.sp,
              ap: player1_data.ap
            },
            user2: %{
              user_id: player2_id,
              card_id: player2_data.card_id,
              sp: player2_data.sp,
              ap: player2_data.ap
            },
            first_user_id: player1_id
          }

          broadcast(state.room_id, "phase_changed:select", broadcast_data)
          new_state = reset_ready_status(updated_state)

          {:noreply, %{new_state | phase: :open_phase_check}}
        else
          {:noreply, state}
        end

      # 現在のフェーズが「カード配置待ち」の場合
      :position_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] All players set card positions")

          # プレイヤーの配置データを整形
          [player1_id, player2_id] = Map.keys(state.players)
          # player1_data = Map.get(state.players, player1_id)
          # player2_data = Map.get(state.players, player2_id)

          # 復活フェイズが必要かチェック（簡略化）
          # TODO: 実際の復活判定ロジックを実装
          has_revival = false

          if has_revival do
            broadcast_data = %{
              status: true,
              user1: %{user_id: player1_id, is_close: true},
              user2: %{user_id: player2_id, is_close: false},
              next_state: 2
            }

            broadcast(state.room_id, "phase_changed:set_to_revival", broadcast_data)
            {:noreply, %{state | phase: :revival_check}}
          else
            # 位置チェックが完了したので、次のフェーズへ
            Logger.info("[#{state.room_id}] Position check completed, moving to open skill check")
            broadcast(state.room_id, "phase_changed:set", %{status: true})
            new_state = reset_ready_status(state)
            {:noreply, %{new_state | phase: :card_select_check}}
          end
        else
          {:noreply, state}
        end

      # オープンスキル待ち(未実装なのでスキップ)
      :open_skill_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] All players finished open skills")
          # 次のフェーズに移行
          new_state = reset_ready_status(state)
          {:noreply, %{new_state | phase: :open_phase_check}}
        else
          {:noreply, state}
        end

      # オープンフェイズ終了待ち
      :open_phase_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] Open phase completed")

          # ターン管理：ターン1の場合はターン終了、それ以外はアクションフェイズ
          if state.turn == 1 do
            Logger.info("[#{state.room_id}] Turn 1 completed, moving to next turn")
            broadcast(state.room_id, "turn_end", %{status: true})
            new_state = reset_ready_status(state)
            # ターンを2に進める
            {:noreply, %{new_state | phase: :position_check, turn: 2}}
          else
            Logger.info(
              "[#{state.room_id}] Turn #{state.turn} open phase completed, moving to action phase"
            )
            # ここからアクションフェイズの処理

            # アクションフェイズ開始時、行動順を決定
            Logger.info("[#{state.room_id}] Action phase started")

            # ← 新しい変数として定義
            action_queue =
              for {player_id, field} <- state.fields do
                for {position, card_data} <- field do
                  # statusがactiveのカードのみ行動順に追加
                  if card_data && Map.get(card_data, :status) == "active" do
                    %{player_id: player_id, position: position, speed: card_data.speed}
                  end
                end
              end
              |> List.flatten()
              # nilを除去
              |> Enum.filter(& &1)
              # 速度順にソート
              |> Enum.sort_by(& &1.speed, :desc)
              # 同じ速度の場合はランダムに順序を入れ替え
              |> Enum.chunk_by(& &1.speed)
              |> Enum.flat_map(&Enum.shuffle/1)
              |> Enum.sort_by(& &1.speed, :desc)

            # 速度順にソート
            Logger.info("[#{state.room_id}] Action queue determined: #{inspect(action_queue)}")

            # 一番速いカードのプレイヤーに操作を促す
            if action_queue != [] do
              # キューから
              first_actor = hd(action_queue)
              Logger.info("[#{state.room_id}] First actor: #{inspect(first_actor)}")
              broadcast(state.room_id, "phase_changed:open", %{status: true, action_user_id: first_actor.player_id})
              # action_queueをStateに保存する, フェーズをアクションフェイズに更新
              new_state = reset_ready_status(state)
              {:noreply, %{new_state | action_queue: action_queue, phase: :action_phase_action_check}}
            else
              Logger.info("[#{state.room_id}] No active cards to act in action phase")
              # 誰もいない場合、アクションフェイズ終了へ
              broadcast(state.room_id, "phase_changed:action", %{status: true})
              new_state = reset_ready_status(state)
              {:noreply, %{new_state | phase: :ready_check, turn: state.turn + 1}}
            end
          end
        else
          {:noreply, state}
        end

      # アクションフェイズ、アクション開始待ち
      :action_phase_start_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] Action phase started")
          # アクション内容をイベント化する

          broadcast(state.room_id, "phase_changed:action", %{status: true})
          new_state = reset_ready_status(state)
          {:noreply, %{new_state | phase: :action_phase_action_check}}
        else
          {:noreply, state}
        end

      # アクションフェイズ、アクション終了待ち
      :action_phase_action_check ->
        if all_players_ready?(state) do
          # 次の行動順を処理
          Logger.info("[#{state.room_id}] Moving to next action in queue")
          # action_queueが空ならアクションフェイズ終了
          if state.action_queue == [] do
            Logger.info("[#{state.room_id}] Action queue empty, moving to action phase end")
            broadcast(state.room_id, "action_phase_end", %{status: true})
            new_state = reset_ready_status(state)
            {:noreply, %{new_state | phase: :action_phase_check}}
          else
            # 次の行動者をdequeueする
            new_state = reset_ready_status(state)
            # action_queueから先頭の要素を取得してから、残りのキューを作成
            [next_actor | remaining_queue] = state.action_queue
            Logger.info("[#{state.room_id}] Next actor: #{inspect(next_actor)}")
            broadcast(state.room_id, "action_next", %{next_actor: next_actor})
            # 新しいstateに残りのキューを設定
            final_state = %{new_state | action_queue: remaining_queue}
            {:noreply, final_state}
          end
        else
          {:noreply, state}
        end

      # アクションフェイズ終了待ち
      :action_phase_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] Action phase completed")
          broadcast(state.room_id, "phase_changed:action", %{status: true})
          new_state = reset_ready_status(state)

          # ゲーム終了条件をチェック（例：10ターンで終了）
          if state.turn >= @max_turns do
            Logger.info("[#{state.room_id}] Game completed after #{state.turn} turns")
            broadcast(state.room_id, "game_end", %{status: true, final_turn: state.turn})
            {:noreply, %{new_state | phase: :game_ended}}
          else
            # アクションフェイズ後は次のターンに進む
            {:noreply, %{new_state | phase: :ready_check, turn: state.turn + 1}}
          end
        else
          {:noreply, state}
        end

      # 復活フェイズ
      :revival_check ->
        if all_players_ready?(state) do
          Logger.info("[#{state.room_id}] Revival phase completed")
          # 復活後はオープンフェイズに移行
          new_state = reset_ready_status(state)
          {:noreply, %{new_state | phase: :open_skill_check}}
        else
          {:noreply, state}
        end

      # ゲーム終了
      :game_ended ->
        Logger.info("[#{state.room_id}] Game has ended, no further actions processed")
        {:noreply, state}

      # 未知のフェーズ
      _ ->
        Logger.warning("[#{state.room_id}] Unknown phase: #{state.phase}")
        {:noreply, state}
    end
  end

  # 全プレイヤーが準備完了かチェック
  defp all_players_ready?(state) do
    # 2人以上いて、全員のreadyがtrueか
    map_size(state.players) >= 2 &&
      Enum.all?(state.players, fn {_id, p_state} -> p_state.ready end)
  end

  # 全員のreadyをfalseに戻す
  defp reset_ready_status(state) do
    new_players =
      for {id, p_state} <- state.players, into: %{} do
        {id, Map.put(p_state, :ready, false)}
      end

    %{state | players: new_players}
  end

  defp broadcast(room_id, event, payload) do
    # ゲーム関連イベントは "room:room_id" チャンネルでブロードキャスト
    AlternativeServerWeb.Endpoint.broadcast("room:" <> room_id, event, payload)
  end

  # プロセス名の生成
  defp via_tuple(room_id) do
    {:via, Registry, {AlternativeServer.GameRegistry, room_id}}
  end

  # setステータスのカードを召喚して、ステータスをactiveに更新する
  defp summon_set_cards(state) do
    Logger.info(
      "[#{state.room_id}] Starting summon_set_cards - current fields: #{inspect(state.fields)}"
    )

    # まず召喚イベントを作成（バリデーション付き）
    {valid_events, errors} =
      for {player_id, field} <- state.fields,
          {position, card_data} <- field,
          card_data && Map.get(card_data, :status) == "set" do
        Logger.info(
          "[#{state.room_id}] Processing summon for player #{player_id}, position #{position}"
        )

        Logger.info("[#{state.room_id}] Card data before summon: #{inspect(card_data)}")

        # card_idの存在チェック（文字列→整数変換も追加）
        raw_card_id = card_data[:card_id] || card_data["card_id"]

        case raw_card_id do
          nil ->
            error_msg = "Card ID is missing for player #{player_id} at position #{position}"
            Logger.error("[#{state.room_id}] #{error_msg}")
            {:error, %{player_id: player_id, position: position, reason: error_msg}}

          id when is_integer(id) and id > 0 ->
            summon_payload = %{
              user_id: player_id,
              position: position,
              card_id: id,
              turn: state.turn
            }

            Logger.info("[#{state.room_id}] Valid summon payload: #{inspect(summon_payload)}")
            {:ok, %{event_type: "summon", payload: summon_payload}}

          # 文字列のcard_idを整数に変換
          string_id when is_binary(string_id) ->
            case Integer.parse(string_id) do
              {parsed_id, ""} when parsed_id > 0 ->
                summon_payload = %{
                  user_id: player_id,
                  position: position,
                  card_id: parsed_id,
                  turn: state.turn
                }

                Logger.info("[#{state.room_id}] Valid summon payload (converted): #{inspect(summon_payload)}")
                {:ok, %{event_type: "summon", payload: summon_payload}}

              _ ->
                error_msg =
                  "Invalid card ID string (#{inspect(string_id)}) for player #{player_id} at position #{position}"

                Logger.error("[#{state.room_id}] #{error_msg}")
                {:error, %{player_id: player_id, position: position, reason: error_msg}}
            end

          invalid_id ->
            error_msg =
              "Invalid card ID (#{inspect(invalid_id)}) for player #{player_id} at position #{position}"

            Logger.error("[#{state.room_id}] #{error_msg}")
            {:error, %{player_id: player_id, position: position, reason: error_msg}}
        end
      end
      |> Enum.split_with(fn {result, _} -> result == :ok end)

    # エラーがある場合の処理
    unless Enum.empty?(errors) do
      error_details = Enum.map(errors, fn {:error, details} -> details end)
      Logger.error("[#{state.room_id}] Summon validation errors: #{inspect(error_details)}")

      # エラー情報をクライアントに通知
      broadcast(state.room_id, "game_error", %{
        type: "summon_validation_failed",
        errors: error_details,
        turn: state.turn
      })

      # エラーがある場合は現在の状態をそのまま返す
      state
    else
      # 有効なイベントのみを抽出
      events = Enum.map(valid_events, fn {:ok, event} -> event end)

      # 召喚イベントをブロードキャスト
      Logger.info("[#{state.room_id}] Broadcasting valid summon events count: #{length(events)}")
      Logger.info("[#{state.room_id}] Broadcasting summon events: #{inspect(events)}")
      broadcast(state.room_id, "event", %{events: events})

      # fieldsのステータスを"set"から"active"に更新（有効なカードのみ）
      new_fields =
        for {player_id, field} <- state.fields, into: %{} do
          updated_field =
            for {position, card_data} <- field, into: %{} do
              if card_data && Map.get(card_data, :status) == "set" do
                # card_idが有効な場合のみactiveに変更（文字列→整数変換も対応）
                raw_card_id = card_data[:card_id] || card_data["card_id"]

                # 整数または有効な文字列かチェック
                valid_card_id = case raw_card_id do
                  id when is_integer(id) and id > 0 -> true
                  string_id when is_binary(string_id) ->
                    case Integer.parse(string_id) do
                      {parsed_id, ""} when parsed_id > 0 -> true
                      _ -> false
                    end
                  _ -> false
                end

                if valid_card_id do
                  updated_card = Map.put(card_data, :status, "active")
                  {position, updated_card}
                else
                  # 無効なcard_idの場合は削除するか、エラー状態にする
                  Logger.warning(
                    "[#{state.room_id}] Removing invalid card at #{player_id}:#{position}"
                  )

                  {position, nil}
                end
              else
                # それ以外はそのまま
                {position, card_data}
              end
            end

          {player_id, updated_field}
        end

      # 更新されたfieldsを返す
      %{state | fields: new_fields}
    end
  end
end

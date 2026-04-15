# WebSocket通信仕様書

このドキュメントでは、ゲームで使用されるWebSocket通信の詳細をまとめています

## 接続情報

### エンドポイント
- WebSocketエンドポイント: `/socket`
- チャンネル形式: `room:{room_id}`

### 認証
接続時に以下のパラメータが必要です:
```javascript
{
  params: {
    token: "Base64エンコードされたセッショントークン"
  }
}
```

## ゲームフロー

### 1. 初期接続・準備フェーズ

#### `finish_ready`
デュエルセッションの開始を通知します。

**送信データ:**
```json
{
  "user_id": "player_id"
}
```

**説明:**
- GameServerが起動していない場合は自動的に起動されます
- プレイヤーをGameServerに登録し、ゲーム状態を初期化します

**受信イベント:** `turn_changed:first`
```json
{
  "status": true,
  "turn": 1
}
```

---

### 2. セットフェーズ

#### `phase_changed:set`
セットフェーズの開始を通知します(受信専用)。

**受信データ:**
```json
{
  "status": true
}
```

**説明:**
- このイベントを受け取ったら、カード選択を開始します

---

#### `select_card`
使用するカードを選択し、属性値を決定します。

**送信データ:**
```json
{
  "user_id": "player_id",
  "card_id": 123,
  "sp": 3,
  "ap": [1, 2, 0, 0]
}
```

**説明:**
- `card_id`: 選択したカードのID(数値)
- `sp`: スキルポイント
- `ap`: 各属性への配分 [Shine, Dark, Flame, Water]
- 両プレイヤーが選択完了すると次のフェーズへ移行します

**受信イベント:** `phase_changed:select`
```json
{
  "status": true,
  "user1": {
    "user_id": "player1",
    "card_id": 123,
    "sp": 3,
    "ap": [1, 2, 0, 0]
  },
  "user2": {
    "user_id": "player2",
    "card_id": 456,
    "sp": 3,
    "ap": [1, 2, 0, 0]
  },
  "first_user_id": "player1"
}
```

---

#### `set_card`
フィールドにカードを配置します。

**送信データ:**
```json
{
  "user_id": "player_id",
  "set_pos": 5
}
```

**説明:**
- `set_pos`: 配置位置(1-9の整数)
- カードデータは送信せず、位置のみを指定します

**受信イベント:** `phase_changed:open`
```json
{
  "status": true,
  "action_user_id": "player1"
}
```

---

### 3. オープンフェーズ

#### `open_phase_end`
オープンフェーズの終了を通知します。

**送信データ:**
```json
{
  "user_id": "player_id"
}
```

**受信イベント(ターン1の場合):** `turn_end`
```json
{
  "status": true
}
```

**受信イベント(ターン2以降):** `phase_changed:action`
```json
{
  "status": true,
  "field1": {
    "user_id": "player1",
    "pos": {
      "pos1": null,
      "pos2": null,
      "pos3": null,
      "pos4": null,
      "pos5": {
        "card_id": 123,
        "is_active": true,
        "is_close": false,
        "hp": 100,
        "level": 1,
        "attack": 50,
        "speed": 3,
        "range": 2
      },
      "pos6": null,
      "pos7": null,
      "pos8": null,
      "pos9": null
    },
    "entry_card": {
      "card_id": 456,
      "set_pos": 7,
      "is_active": false,
      "is_close": true,
      "hp": 80,
      "level": 1,
      "attack": 40,
      "speed": 2,
      "range": 1
    }
  },
  "field2": {
    "user_id": "player2",
    "pos": { /* 同様の構造 */ },
    "entry_card": { /* 同様の構造 */ }
  },
  "next_state": 4
}
```

**説明:**
- `field1`, `field2`: 両プレイヤーのフィールド状態
- `pos`: フィールド上の9つのポジション(1-9)
- `entry_card`: 次ターンに召喚予定のカード
- `next_state`: 次のゲーム状態

---

### 4. アクションフェーズ

#### `action_card`
カードアクションを実行します(ターゲット不要)。

**送信データ:**
```json
{
  "user_id": "player_id",
  "action_id": 1
}
```

**説明:**
- `action_id`: 実行するアクションのID(数値)

---

#### `action_card_with_target`
カードアクションを実行します(ターゲット指定あり)。

**送信データ:**
```json
{
  "user_id": "player_id",
  "action_id": 1,
  "target_id": "target_instantiate_id"
}
```

**説明:**
- `action_id`: 実行するアクションのID(数値)
- `target_id`: ターゲットのinstantiate_id(文字列)

---

## ゲーム状態の通知イベント

### `turn_changed:first`
最初のターン開始時に送信されます。

```json
{
  "status": true,
  "turn": 1
}
```

---

### `turn_changed:main`
ターンが変更された際に送信されます。

```json
{
  "status": true,
  "turn": 2
}
```

---

### `event`
ゲーム内イベント(召喚など)が発生した際に送信されます。

```json
{
  "events": [
    {
      "event_type": "summon",
      "payload": {
        "user_id": "player1",
        "position": 5,
        "card_id": 123,
        "instantiate_id": "uuid-v4-string",
        "turn": 2
      }
    }
  ]
}
```

**イベントタイプ:**
- `summon`: カードの召喚
- `attack`: 攻撃(将来実装予定)
- `move`: 移動(将来実装予定)

**payloadの構造:**
- `event_type`によって`payload`の形式が異なります
- 単一のオブジェクトまたは配列として送信される可能性があります

---

### `turn_end`
ターン終了時に送信されます。

```json
{
  "status": true
}
```

---

## フェーズ遷移イベント一覧

| イベント名 | 説明 | 次のアクション |
|-----------|------|--------------|
| `turn_changed:first` | 最初のターン開始 | ゲーム開始処理 |
| `turn_changed:main` | メインターン開始 | ターン開始処理 |
| `phase_changed:set` | セットフェーズ開始 | カード選択 |
| `phase_changed:select` | カード選択完了 | カード配置 |
| `phase_changed:open` | オープンフェーズ開始 | オープンフェーズ処理 |
| `phase_changed:action` | アクションフェーズ開始 | アクション選択 |
| `turn_end` | ターン終了 | 次ターンへ |

---

## エラーハンドリング

接続エラーや認証エラーが発生した場合:

```json
{
  "reason": "unauthorized"
}
```

DuelSocket.csでは、接続失敗時に以下の処理を実行します:
- `_connectionFailed`フラグを`true`に設定
- 以降のネットワーク処理をスキップ
- エラーログを出力

---

## 実装例(C# Unity)

```csharp
// 接続
SetSocket();

// イベントリスナー設定
_roomChannel.On("turn_changed:first", (TurnStatus payload) =>
{
    StartDuelFunc(payload);
});

_roomChannel.On("phase_changed:set", (Status payload) => 
{
    StartSelectPhase(payload.status);
});

_roomChannel.On("event", (Event payload) => 
{
    HandleEvent(payload);
});

// カード選択送信
SetCardMessage message = new SetCardMessage();
message.user_id = PlayerData.UserID;
message.card_id = 123;
message.sp = 3;
message.ap = new List<int> { 1, 2, 0, 0 };
_roomChannel.Push("select_card", message);
```

---

## データ型の定義

### FieldCardData
```csharp
{
    "card_id": 123,           // int: カードID
    "is_active": true,        // bool: アクティブ状態
    "is_close": false,        // bool: 伏せ状態
    "hp": 100,                // int: HP
    "level": 1,               // int: レベル
    "attack": 50,             // int: 攻撃力
    "speed": 3,               // int: 速度
    "range": 2                // int: 射程
}
```

### EntryCardData
```csharp
{
    "card_id": 123,           // int: カードID
    "set_pos": 5,             // int: 配置位置(1-9)
    "is_active": false,       // bool: アクティブ状態
    "is_close": true,         // bool: 伏せ状態
    "hp": 100,                // int: HP
    "level": 1,               // int: レベル
    "attack": 50,             // int: 攻撃力
    "speed": 3,               // int: 速度
    "range": 2                // int: 射程
}
```

---

## 注意事項

1. **非同期処理**: 各アクションはGameServerで非同期に処理されます
2. **待機状態**: プレイヤーのアクション完了後、`IsWait`フラグが`true`に設定されます
3. **フェーズ遷移**: 両プレイヤーが準備完了すると自動的に次のフェーズへ移行します
4. **ターン管理**: ターン1は特別扱いで、セットフェーズとオープンフェーズのみ実行されます
5. **召喚処理**: ターン2以降、カード配置時に前のターンで選択したカードが召喚されます
6. **接続エラー**: 接続に失敗した場合、`_connectionFailed`フラグにより以降の処理がスキップされます
7. **データ型**: カードIDやアクションIDは数値型、user_idやinstantiate_idは文字列型です

---

## 関連ファイル

- GameServer実装: `lib/alternativeServer/game_server.ex`
- Channel実装: `lib/alternativeServer_web/channels/room_channel/room_channel_game.ex`

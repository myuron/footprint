# Claude Code セッション JSONL 構造仕様

`~/.claude/projects/` 配下に保存される Claude Code のセッションログ(JSONL)の構造仕様。

- 調査日: 2026-07-13
- 調査対象: ローカル環境の実ファイル(Claude Code v2.1.170 〜 v2.1.207 で生成された約 1.6 万レコード)
- 参考: https://claude-dev.tools/docs/jsonl-format

> **注意**: このフォーマットは公式に安定性が保証されたものではなく、Claude Code のバージョンごとにフィールドが追加・変更される。パーサは**未知のフィールド・未知の type を許容する**設計にすること(`#[serde(deny_unknown_fields)]` は使わない)。

## 1. ファイル配置

```
~/.claude/projects/
└── <エンコード済みプロジェクトパス>/
    ├── <session-uuid>.jsonl          # メインセッションのログ(追記専用)
    ├── <session-uuid>/               # セッション付随データ(存在しない場合もある)
    │   └── subagents/
    │       ├── agent-<agent-id>.jsonl      # サブエージェントの会話ログ
    │       └── agent-<agent-id>.meta.json  # サブエージェントのメタ情報
    └── memory/                       # 自動メモリ(MEMORY.md ほか)※セッションログではない
```

- **プロジェクトパスのエンコード**: 作業ディレクトリの絶対パスの `/` と `.` を `-` に置換したもの。
  例: `/home/myuron/src/github.com/myuron/footprint` → `-home-myuron-src-github-com-myuron-footprint`
- **JSONL**: 1 行 = 1 つの JSON オブジェクト(イベント)。ファイルは追記専用で、行は概ね時系列順。
- **サブエージェント**: `Task`/`Agent` ツールで起動されたサブエージェントの会話は、メインの jsonl ではなく `<session-uuid>/subagents/agent-*.jsonl` に分離して保存される。レコード構造はメインと同じだが `isSidechain: true` になる。
  `agent-*.meta.json` の例:

  ```json
  {
    "agentType": "general-purpose",
    "description": "...",
    "toolUseId": "toolu_01...",
    "spawnDepth": 1
  }
  ```

## 2. レコードタイプ一覧

`type` フィールドで判別する。実測で確認された 13 種類:

| type                    | 分類 | 内容                                                                  |
| ----------------------- | ---- | --------------------------------------------------------------------- |
| `user`                  | 会話 | ユーザ入力・ツール実行結果                                            |
| `assistant`             | 会話 | モデル応答(テキスト・思考・ツール呼び出し)                            |
| `system`                | 会話 | システムイベント(subtype で細分化)                                    |
| `attachment`            | 会話 | ターンに添付されるコンテキスト情報(subtype 多数)                      |
| `file-history-snapshot` | 状態 | 編集ファイルのバックアップ追跡スナップショット                        |
| `queue-operation`       | 状態 | 入力キュー(プロンプトの enqueue/dequeue/remove)                       |
| `mode`                  | 状態 | モード変更(例: `normal`)                                              |
| `permission-mode`       | 状態 | パーミッションモード変更(`default` / `plan` / `acceptEdits` / `auto`) |
| `last-prompt`           | 状態 | 最後のプロンプト位置(`leafUuid`)                                      |
| `ai-title`              | メタ | AI が生成したセッションタイトル                                       |
| `custom-title`          | メタ | ユーザが設定したセッションタイトル                                    |
| `agent-name`            | メタ | セッションのエージェント名                                            |
| `pr-link`               | メタ | セッションに紐づく GitHub PR                                          |

会話レコード(`user` / `assistant` / `system` / `attachment`)は共通エンベロープ(§3)を持つ。
状態・メタ系レコードは `sessionId` + type 固有フィールドのみの小さなオブジェクト。

ファイルの先頭行は `mode`、`queue-operation`、`last-prompt` のいずれかで始まるパターンが確認されている(会話開始前に状態レコードが書かれるため)。

## 3. 共通エンベロープ(会話レコード)

`user` / `assistant` / `system` / `attachment` が共通で持つフィールド:

| フィールド    | 型             | 説明                                                                                            |
| ------------- | -------------- | ----------------------------------------------------------------------------------------------- |
| `type`        | string         | レコードタイプ                                                                                  |
| `uuid`        | string (UUID)  | このレコードの一意 ID                                                                           |
| `parentUuid`  | string \| null | 親レコードの uuid。会話ツリーを構成する。ターン先頭は null                                      |
| `timestamp`   | string         | ISO 8601 (UTC, ミリ秒) 例: `"2026-07-12T11:03:23.435Z"`                                         |
| `sessionId`   | string (UUID)  | セッション ID(= ファイル名)                                                                     |
| `session_id`  | string         | `sessionId` と同値のことも別値のこともある(resume 時に元セッションの ID が入る)。無い場合もある |
| `cwd`         | string         | イベント発生時の作業ディレクトリ                                                                |
| `gitBranch`   | string         | 現在のブランチ。detached 時は `"HEAD"`、リポジトリ外は空文字                                    |
| `version`     | string         | 書き込んだ Claude Code のバージョン(例: `"2.1.204"`)                                            |
| `userType`    | string         | 実測では常に `"external"`                                                                       |
| `entrypoint`  | string         | `"cli"` / `"sdk-cli"` / `"sdk-ts"`                                                              |
| `isSidechain` | bool           | サブエージェント(subagents/ 配下)なら true。メインログでは false                                |
| `slug`        | string?        | セッションの人間可読スラッグ(例: `"cheeky-bouncing-rabbit"`)。無い場合もある                    |
| `isMeta`      | bool?          | true ならユーザの発話ではなく内部注入されたコンテキスト(例: `/context` の出力)                  |

**会話ツリー**: レコードは `parentUuid` → `uuid` の親子チェーンで DAG(実質は木)を構成する。中断や再送があると同じ親から複数の子が生える(分岐)。UI で「現在の会話」を復元するには `last-prompt` の `leafUuid` から親を遡るのが確実。

## 4. `type: "user"`

ユーザ入力、またはツール実行結果を運ぶレコード。

```json
{
  "type": "user",
  "parentUuid": "7b92278a-...",
  "isSidechain": false,
  "promptId": "e09d9ce6-...",
  "message": { "role": "user", "content": "..." },
  "uuid": "4441b37b-...",
  "timestamp": "2026-07-08T12:00:11.506Z",
  "userType": "external",
  "entrypoint": "cli",
  "cwd": "/home/myuron",
  "sessionId": "d12791bc-...",
  "version": "2.1.204",
  "gitBranch": "HEAD"
}
```

### message.content の形

- **string**: 素のプロンプト。スラッシュコマンドは `<command-name>/foo</command-name>\n<command-message>...</command-message>\n<command-args>...</command-args>` 形式、ローカルコマンド出力は `<local-command-stdout>...</local-command-stdout>` 形式で埋め込まれる。
- **array**: content ブロックの配列。実測で確認されたブロック:
  - `{"type":"text","text":"..."}`
  - `{"type":"image","source":{...}}`
  - `{"type":"tool_result","tool_use_id":"toolu_...","content":<string|array>,"is_error":true?}` — 直前の assistant の `tool_use` に対応する実行結果。`content` は文字列またはブロック配列(text/image)。

### user 固有のオプションフィールド

| フィールド                  | 型               | 説明                                                                      |
| --------------------------- | ---------------- | ------------------------------------------------------------------------- |
| `promptId`                  | string (UUID)    | 同一プロンプト起点のターンをまとめる ID                                   |
| `origin`                    | object           | 入力の出所。実測: `{"kind":"human"}` / `{"kind":"task-notification"}`     |
| `promptSource`              | string           | `"typed"` / `"queued"` / `"sdk"` / `"system"` / `"suggestion_accepted"`   |
| `permissionMode`            | string           | 入力時のパーミッションモード                                              |
| `imagePasteIds`             | array            | 画像ペーストの ID 一覧                                                    |
| `isMeta`                    | bool             | 内部注入コンテキスト(表示上は「ユーザ発話」ではない)                      |
| `isCompactSummary`          | bool             | コンパクト(要約)によって注入された要約メッセージ                          |
| `isVisibleInTranscriptOnly` | bool             | transcript 表示専用(API には送られない文脈)                               |
| `interruptedMessageId`      | string           | ユーザ割り込みで中断された assistant メッセージの ID                      |
| `toolUseResult`             | string \| object | ツール実行結果の構造化データ(§4.1)                                        |
| `sourceToolAssistantUUID`   | string           | この tool_result の元となった `tool_use` を含む assistant レコードの uuid |
| `sourceToolUseID`           | string           | 関連する tool_use ID(isMeta なコンテキスト注入時)                         |
| `toolDenialKind`            | string           | ツール実行が拒否された場合の種別                                          |

### 4.1 toolUseResult

`tool_result` を含む user レコードに付く、ツールごとの構造化結果。`message.content` 内の tool_result が「モデルに見せた文字列」なのに対し、こちらは UI 用のリッチデータ。形はツール依存で、代表例:

| ツール          | 主なキー                                                                                                                                |
| --------------- | --------------------------------------------------------------------------------------------------------------------------------------- |
| Bash            | `stdout`, `stderr`, `interrupted`, `isImage`, `noOutputExpected`, (`backgroundTaskId`, `returnCodeInterpretation`, `gitOperation` など) |
| Read            | `type: "text"`, `file: {filePath, content, numLines, startLine, totalLines}`                                                            |
| Edit            | `filePath`, `oldString`, `newString`, `originalFile`, `structuredPatch`, `replaceAll`, `userModified`                                   |
| Write           | `type: "create"/"update"`, `filePath`, `content`, `structuredPatch`                                                                     |
| Task/Agent      | `agentId`, `status`, `prompt`, `resolvedModel`, (`content`, `usage`, `totalTokens` など)                                                |
| WebFetch        | `url`, `code`, `result`, `durationMs`, `bytes`                                                                                          |
| WebSearch       | `query`, `results`, `durationSeconds`, `searchCount`                                                                                    |
| AskUserQuestion | `questions`, `answers`, `annotations`                                                                                                   |
| (エラー時)      | 文字列(エラーメッセージそのもの)                                                                                                        |

網羅列挙はせず、「任意の JSON 値」として扱うのが安全。

## 5. `type: "assistant"`

モデル応答。`message` に Anthropic API の Message オブジェクト(ほぼ)そのままが入る。

```json
{
  "type": "assistant",
  "parentUuid": "84c77e84-...",
  "message": {
    "id": "msg_01ReTP...",
    "type": "message",
    "role": "assistant",
    "model": "claude-fable-5",
    "content": [ ... ],
    "stop_reason": "tool_use",
    "stop_sequence": null,
    "stop_details": null,
    "usage": { ... },
    "diagnostics": null
  },
  "requestId": "req_011Cci...",
  "uuid": "fe0fbcd0-...", "timestamp": "...", ...
}
```

- 1 回の API 応答が **content ブロックごとに複数の assistant レコードに分割**されて書かれることがある(`message.id` が同じで `uuid` が異なる)。表示時は `message.id` でまとめると自然。

### content ブロック

| ブロック   | フィールド                                                                                                 |
| ---------- | ---------------------------------------------------------------------------------------------------------- |
| `text`     | `text`                                                                                                     |
| `thinking` | `thinking`, `signature`(署名。表示不要)                                                                    |
| `tool_use` | `id`(`toolu_...`), `name`(Bash, Read, Edit, ...), `input`(ツール固有), `caller`(実測: `{"type":"direct"}`) |

### usage

```json
{
  "input_tokens": 3208,
  "output_tokens": 225,
  "cache_creation_input_tokens": 3876,
  "cache_read_input_tokens": 10540,
  "cache_creation": {"ephemeral_5m_input_tokens": 0, "ephemeral_1h_input_tokens": 3876},
  "service_tier": "standard",
  "speed": "standard",
  "inference_geo": "not_available",
  "server_tool_use": {"web_search_requests": 0},
  "iterations": [ {"type":"message", "input_tokens": ..., ...} ]
}
```

- `stop_reason`: 実測で `"tool_use"` / `"end_turn"` / `"stop_sequence"` / `"max_tokens"`。

### assistant 固有のオプションフィールド

| フィールド           | 型     | 説明                                                   |
| -------------------- | ------ | ------------------------------------------------------ |
| `requestId`          | string | API リクエスト ID(`req_...`)。エラー時は無いこともある |
| `isApiErrorMessage`  | bool   | API エラーを表す合成メッセージ                         |
| `apiErrorStatus`     | number | エラー時の HTTP ステータス                             |
| `error`              | object | エラー詳細                                             |
| `attributionSkill`   | string | 応答に寄与したスキル名                                 |
| `slug`, `session_id` | string | §3 参照                                                |

## 6. `type: "system"`

`subtype` で細分化されるシステムイベント。`level`(`info` / `warning` / `error` / `notice` / `suggestion`)を持つものがある。

| subtype             | 説明                                      | 主な固有フィールド                                                                                                                                                 |
| ------------------- | ----------------------------------------- | ------------------------------------------------------------------------------------------------------------------------------------------------------------------ |
| `turn_duration`     | ターン所要時間                            | `durationMs`, `messageCount`, (`pendingBackgroundAgentCount`)                                                                                                      |
| `local_command`     | ローカルコマンド(`/context` 等)の実行記録 | `content`(command-name タグ形式)                                                                                                                                   |
| `away_summary`      | 離席中の作業サマリ                        | `content`                                                                                                                                                          |
| `api_error`         | API エラーとリトライ                      | `error` {message, status, requestId, ...}, `retryInMs`, `retryAttempt`, `maxRetries`                                                                               |
| `compact_boundary`  | コンテキスト圧縮の境界                    | `compactMetadata` {trigger: "manual"/"auto", preTokens, postTokens, cumulativeDroppedTokens, durationMs, preservedSegment, preservedMessages}, `logicalParentUuid` |
| `stop_hook_summary` | Stop フック実行結果                       | `hookCount`, `hookInfos`, `hookErrors`, `hookAdditionalContext`, `preventedContinuation`, `stopReason`, `hasOutput`, `toolUseID`                                   |
| `informational`     | 通知(例: Unknown command)                 | `content`                                                                                                                                                          |

**compact の流れ**: `compact_boundary`(`parentUuid: null`, `logicalParentUuid` = 圧縮前の末尾)→ その子として `isCompactSummary: true` の user レコード(要約文)が続く。

## 7. `type: "attachment"`

ターンに付随してコンテキストとして注入される情報。本体は `attachment` フィールドのオブジェクトで、`attachment.type` で細分化。共通エンベロープ(§3)を持つ。

実測で確認された `attachment.type`(頻度順):

| attachment.type                                                               | 内容                                                                                                      |
| ----------------------------------------------------------------------------- | --------------------------------------------------------------------------------------------------------- |
| `skill_listing`                                                               | 利用可能スキル一覧                                                                                        |
| `agent_listing_delta`                                                         | 利用可能エージェント一覧の差分                                                                            |
| `deferred_tools_delta`                                                        | 遅延ロードツール一覧の差分                                                                                |
| `task_reminder`                                                               | タスクリストのリマインダ(`content`, `itemCount`)                                                          |
| `hook_success`                                                                | フック成功(`hookName`, `hookEvent`, `toolUseID`, `stdout`, `stderr`, `exitCode`, `command`, `durationMs`) |
| `hook_system_message` / `hook_non_blocking_error` / `hook_additional_context` | フック関連メッセージ                                                                                      |
| `edited_text_file`                                                            | 外部で編集されたファイルの通知(`filename`, `snippet`)                                                     |
| `file`                                                                        | 読み込んだファイル内容(`filename`, `content.file.{filePath, content}`)                                    |
| `already_read_file`                                                           | 既読ファイルの再読み込み抑止                                                                              |
| `queued_command`                                                              | キュー投入されたプロンプト(`prompt`)                                                                      |
| `command_permissions`                                                         | コマンドのパーミッション情報                                                                              |
| `date_change`                                                                 | 日付変更(`newDate`)                                                                                       |
| `plan_mode` / `plan_mode_exit`                                                | プランモード関連(`reminderType`, `planFilePath`, `planExists` 等)                                         |
| `invoked_skills`                                                              | 呼び出されたスキル                                                                                        |
| `goal_status`                                                                 | ゴールステータス                                                                                          |
| `compact_file_reference`                                                      | 圧縮時のファイル参照                                                                                      |

一覧はバージョンとともに増える。未知の attachment.type を許容すること。

## 8. 状態・メタ系レコード

共通エンベロープを持たない小さなレコード。同じ type が状態変化のたびに何度も書かれる(**最後の値が現在値**)。

```jsonc
// セッション状態
{"type":"mode","mode":"normal","sessionId":"..."}
{"type":"permission-mode","permissionMode":"default","sessionId":"..."}  // default | plan | acceptEdits | auto
{"type":"last-prompt","leafUuid":"cfd66092-...","sessionId":"..."}       // lastPrompt (string) を持つ場合もある

// タイトル・名前
{"type":"ai-title","aiTitle":"init.elの起動メカニズムの確認","sessionId":"..."}
{"type":"custom-title","customTitle":"...","sessionId":"..."}
{"type":"agent-name","agentName":"emacs-agent-shell-setup","sessionId":"..."}

// PR リンク
{"type":"pr-link","sessionId":"...","prNumber":2,"prUrl":"https://github.com/...","prRepository":"myuron/bridge","timestamp":"..."}

// 入力キュー操作(operation: enqueue | dequeue | remove。enqueue は content を持つ)
{"type":"queue-operation","operation":"enqueue","timestamp":"...","sessionId":"...","content":"..."}

// ファイル履歴スナップショット(編集の undo 用バックアップ追跡)
{"type":"file-history-snapshot","messageId":"3227f2bb-...","isSnapshotUpdate":false,
 "snapshot":{"messageId":"...","timestamp":"...",
   "trackedFileBackups":{"docs/spec/s3-mvp.md":{"backupFileName":null,"version":1,"backupTime":"..."}}}}
```

- `ai-title` は生成のたびに追記されるため 1 セッションに複数回現れる。**セッションタイトルは最後の `ai-title`(`custom-title` があればそちら優先)**。
- `last-prompt.leafUuid` は会話ツリーの現在の葉を指す。resume・分岐後の「表示すべき系列」の特定に使える。

## 9. パーサ実装上の注意(footprint 向け)

1. **寛容にパースする**: 未知の `type` / `subtype` / `attachment.type` / フィールドはスキップまたは生 JSON として保持する。バージョン間でキー集合が揺れる(実測で user だけで 28 通りのキー集合)。
2. **1 行ずつ独立してパース**: 壊れた行(書き込み途中など)があっても他の行の処理を続ける。
3. **表示の基本単位**は会話レコード(user / assistant / system)。`attachment` と `isMeta: true` の user はコンテキストノイズなので、デフォルトでは折り畳み・非表示が妥当。
4. **assistant の分割**: 同じ `message.id` を持つ連続レコードは 1 つの応答としてまとめる。
5. **ツール呼び出しの対応付け**: assistant の `tool_use.id` ⇔ user の `tool_result.tool_use_id` で紐づける。リッチ表示には `toolUseResult` を使う。
6. **時系列 vs ツリー**: 行順は概ね時系列だが、分岐(リトライ・割り込み)があるため、正確な会話再構成は `parentUuid` チェーン + `leafUuid` を使う。
7. **トークン集計**: `assistant.message.usage` を合算。ただし同一 `message.id` の分割レコードで usage が重複するため、`message.id`(または `requestId`)単位でユニーク化してから合算する。
8. **サブエージェント**: `<session-uuid>/subagents/*.jsonl` を辿ると Task ツールの中身が見られる。`toolUseId`(meta.json)でメインログの `tool_use` と対応付け可能。

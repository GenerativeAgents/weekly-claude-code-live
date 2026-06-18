# 権限リレー機能を追加しました `--channels`。権限機能を宣言するチャネルサーバーは、ツールの承認プロンプトをスマートフォンに転送できます。

対象バージョン: Claude Code 2.1.81（権限リレー）/ channels 自体は 2.1.80 以降。

## 疑問

changelog 1 行だけだと、何と何がつながって「スマホに承認が飛ぶ」のか分からなかった。

- そもそも `--channels` とは何のフラグなのか（チャネル = 普通の MCP サーバーと何が違う？）
- 「権限機能を宣言する」とは具体的に何を宣言するのか
- 承認プロンプトがスマホに飛んで、そこで OK したら手元の Claude Code がどう再開するのか
- ローカル端末の承認ダイアログはどうなるのか（消える？両方生きてる？）
- セキュリティ的に危なくないのか（誰でも承認できたら困る）

## まとめ（先に結論）

- **チャネル = push 型の MCP サーバー**。普通の MCP は Claude が必要なときに「引きに行く」
  pull 型。チャネルは外部イベントを起きたそばから**セッションに割り込ませる** push 型。
  `claude/channel` capability を宣言した MCP サーバーがチャネルになる。
- **`--channels` はそのセッションでどのチャネルを有効化するかを選ぶフラグ**。
  `.mcp.json` に置いてあるだけでは push されない。`--channels` で名指しして初めて届く。
- **権限リレー = チャネルが `claude/channel/permission` capability を追加宣言**すると、
  Claude Code がツール承認プロンプトを**そのチャネル経由で別デバイスにも転送**する。
  スマホ側で `yes <id>` / `no <id>` と返すと、その verdict が Claude Code に戻る。
- **ローカル端末のダイアログは開いたまま**。端末・リモートのうち**先に答えた方が採用**され、
  もう片方は破棄される。

出典:
[channels.md](https://code.claude.com/docs/en/channels.md) /
[channels-reference.md](https://code.claude.com/docs/en/channels-reference.md)

## `--channels` とは — push 型 MCP サーバーの有効化フラグ

> A channel is an MCP server that pushes events into your running Claude Code session,
> so Claude can react to things that happen while you're not at the terminal.
> — channels.md

普通の MCP サーバーとの対比:

| | 普通の MCP サーバー | チャネル |
| --- | --- | --- |
| 方向 | pull（Claude が問い合わせる） | push（サーバーがセッションに割り込む） |
| いつ届く | タスク中に Claude が呼んだとき | 外部でイベントが起きたとき（在席不要） |
| 宣言 | tools / resources など | `experimental['claude/channel']` |
| 届くイベント | ツール結果 | `<channel source="...">…</channel>` タグ |

チャネルは一方向（CI/監視 webhook を流し込むだけ）と双方向（チャット橋渡し。`reply`
ツールを生やして Claude が返信できる）がある。Telegram / Discord / iMessage / fakechat が
research preview の公式チャネル。

**重要な制約**:

> Being in `.mcp.json` isn't enough to push messages: a server also has to be named in
> `--channels`. — channels.md

つまり「設定に存在する」と「このセッションで push を許す」は別レイヤー。`--channels` は
後者を**セッション単位で明示オプトイン**する安全弁になっている。

```bash
# 識別子は 2 形式（スペース区切りで複数可）
claude --channels plugin:telegram@claude-plugins-official   # plugin:<name>@<marketplace>
claude --channels server:webhook                            # server:<name>（.mcp.json）
```

## 権限リレー — 今日の主役（2.1.81+）

> Permission relay requires Claude Code v2.1.81 or later. Earlier versions ignore the
> `claude/channel/permission` capability. — channels-reference.md

### 「権限機能を宣言する」の中身

チャネルサーバーが MCP `Server` コンストラクタの capability に **2 つ目の鍵**を足すだけ:

```ts
capabilities: {
  experimental: {
    'claude/channel': {},             // チャネルである宣言
    'claude/channel/permission': {},  // ← これが「権限機能の宣言」。リレーにオプトイン
  },
  tools: {},
}
```

これを宣言したチャネルにだけ、Claude Code は承認プロンプトを転送する。

### エンドツーエンドの流れ（4 ステップ）

承認待ちでローカル端末のダイアログが開くと、**並行して**リレーループが回る:

1. Claude Code が短い request ID を生成し、サーバーに
   `notifications/claude/channel/permission_request` を送る
2. サーバーがプロンプト＋ID を整形して、自分のプラットフォーム（チャット/スマホ）へ送る
3. リモートのユーザーが `yes <id>` / `no <id>` で返信する
4. サーバーの inbound ハンドラが返信を verdict に変換し
   `notifications/claude/channel/permission` で Claude Code に返す。
   **Claude Code は自分が発行した ID に一致する verdict だけ**を受理する

**outbound（Claude Code → サーバー）`permission_request` の params（全部 string）**:

| フィールド | 中身 |
| --- | --- |
| `request_id` | 小文字 5 文字（`a`-`z` から `l` を除外）。スマホ入力で `1`/`I` と紛れないため。**ローカル端末のダイアログにはこの ID は出ない**ので、リレーで知るしかない |
| `tool_name` | `Bash` / `Write` など |
| `description` | この呼び出しが何をするかの人間向け要約（端末ダイアログと同じ文言） |
| `input_preview` | ツール引数の JSON 文字列（200 文字に切り詰め） |

**inbound（サーバー → Claude Code）`permission` の params**:

| フィールド | 中身 |
| --- | --- |
| `request_id` | 上の ID をそのまま返す（大文字化された autocorrect は小文字へ正規化） |
| `behavior` | `'allow'` または `'deny'`。allow で続行、deny で拒否（ローカルで No と同じ） |

### ローカル端末と先着優先

> The local terminal dialog stays open through all of this. If someone at the terminal
> answers before the remote verdict arrives, that answer is applied instead and the
> pending remote request is dropped. — channels-reference.md

- 端末ダイアログとリモート、**両方が同時に生きている**。
- **先に答えた方が採用**され、もう一方は破棄。
- ID 不一致 / フォーマット違いの返信は黙って捨てられ、ダイアログは開いたまま。
- 1 回の verdict はその呼び出し限り。将来の呼び出しには影響しない。

### リレーされる / されない承認

> Relay covers tool-use approvals like `Bash`, `Write`, and `Edit`. Project trust and
> MCP server consent dialogs don't relay; those only appear in the local terminal.
> — channels-reference.md

- **リレーされる**: `Bash` / `Write` / `Edit` などツール使用の承認
- **リレーされない**: プロジェクト信頼ダイアログ、MCP サーバー利用同意ダイアログ
  （これらは端末でしか出ない）

## セットアップと組織コントロール

ユーザー操作（Telegram 例）:

```bash
/plugin install telegram@claude-plugins-official   # 1. インストール
/reload-plugins                                    #    configure コマンド有効化
/telegram:configure <bot-token>                    # 2. 資格情報（~/.claude/channels/telegram/.env）
# 3. 再起動してチャネル有効化
claude --channels plugin:telegram@claude-plugins-official
# 4. bot に何か送る → 返ってきた pairing code を承認
/telegram:access pair <code>
/telegram:access policy allowlist                  #    自分以外を締め出す
```

組織（Team/Enterprise/managed Console）の管理設定（ユーザーは上書き不可）:

| 設定 | 役割 | 未設定時 |
| --- | --- | --- |
| `channelsEnabled` | マスタースイッチ。true でないとどのチャネルも届かない（開発フラグ含め全部ブロック） | claude.ai Team/Enterprise: ブロック / Console: managed settings 未配備なら許可 |
| `allowedChannelPlugins` | 登録可能なプラグインの allowlist。設定すると Anthropic 既定リストを**置き換える** | Anthropic 既定リストが適用 |

Pro/Max の個人（組織なし）はこのチェックを丸ごとスキップ。`--channels` でオプトインするだけ。

開発中の自作チャネルは allowlist 外なので `--dangerously-load-development-channels` で
ローカルテストする（エントリ単位の bypass。`channelsEnabled` ポリシーは依然有効）。

## セキュリティ（権限リレーで特に重要）

> Every approved channel plugin maintains a sender allowlist: only IDs you've added can
> push messages, and everyone else is silently dropped. — channels.md

> The allowlist also gates permission relay if the channel declares it. Anyone who can
> reply through the channel can approve or deny tool use in your session, so only
> allowlist senders you trust with that authority. — channels.md

- ゲートなしチャネルは**プロンプトインジェクションの経路**そのもの。送信者を必ず
  allowlist で照合してから `mcp.notification()` する。
- リレーを宣言するなら**特に厳しく**: チャネル経由で返信できる人は誰でもセッションの
  ツール実行を許可/拒否できてしまう。グループでは「部屋 ID」ではなく**送信者 ID**で照合。

## 前提・制約

- Claude Code v2.1.80+（リレーは v2.1.81+）
- Anthropic 認証（claude.ai or Console API key）。**Bedrock / Vertex / Foundry では不可**
- 公式チャネルプラグインの実行に Bun（自作は Node/Deno でも可。要 `@modelcontextprotocol/sdk`）
- `-p`（非対話）では端末入力が要るツール（複数選択・plan 承認など）は無効化され、停止しない
- research preview。`--channels` の構文・プロトコルは今後変わりうる

## 他機能との使い分け（docs の比較表より）

- **チャネル**: 非 Claude ソースのイベントを**既に開いているローカルセッションに push**
- **Claude Code on the web / Slack**: 新しいクラウドセッションを spawn
- **標準 MCP**: pull。Claude が必要時に問い合わせる
- **Remote Control**: claude.ai / モバイルアプリから**手元のセッションを操縦**する
  （こちらは「操縦」、チャネルは「イベント流入」。承認をスマホで、なら用途が近い）

## デモ

スマホ実機・Telegram bot 不要で、**curl を「スマホ」に見立てて権限リレーの一周を
ローカル完結で再現**する self-contained デモを [demo/](./demo/) 配下に置いた。
ドキュメントの Bun 製 `webhook.ts`（permission relay 版）を Node.js に移植してあり、
当日の手順は [demo/README.md](./demo/README.md)。実行は必ず `demo/` に `cd` してから。

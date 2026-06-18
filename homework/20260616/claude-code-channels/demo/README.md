# 権限リレー (`--channels`) デモ手順 — スマホ無しで「承認をスマホに転送」を再現

changelog の主役は **「チャネルサーバーがツール承認プロンプトをスマホに転送できる」**。
このデモは Telegram bot もスマホ実機も使わず、**`curl` を「スマホ」に見立てて**
権限リレーの一周をローカル完結で見せる。

仕掛けは公式ドキュメントの
[channels-reference.md — Relay permission prompts](https://code.claude.com/docs/en/channels-reference.md#relay-permission-prompts)
の "Full webhook.ts with permission relay"（Bun 版）を **Node.js に移植**した
[`relay-channel.mjs`](./relay-channel.mjs)。当日見せる鍵は 3 つ:

1. `experimental['claude/channel/permission'] = {}` の**宣言**（= 権限機能の宣言）
2. `notifications/claude/channel/permission_request` を受け取り、プロンプト＋ID を
   `/events`（SSE）に流す → **`curl -N` の画面が「スマホの通知」**
3. inbound で `yes <id>` / `no <id>` を拾って verdict を返す → **`curl` で yes = スマホでタップ**

スタイルは前回（`--agent`）踏襲: このディレクトリに `cd` してから実行する。
`.mcp.json` が cwd 配下で project 設定として解決されるため。

---

## 前提

- **Claude Code v2.1.81 以降**（権限リレーは 2.1.81+。`claude --version` で確認）
- **Anthropic 認証**（claude.ai ログイン or Console API key）。Bedrock/Vertex/Foundry は不可
- 組織アカウントの場合、管理者が `channelsEnabled: true` を有効化済みであること
  （Pro/Max 個人はチェック無し）
- **Node.js**（このデモは Bun 不要。`node --version`）
- ポート **8788** が空いていること

## 事前準備（1 回だけ）

```bash
cd homework/20260616/claude-code-channels/demo
npm install        # @modelcontextprotocol/sdk と zod を入れる
```

サーバ単体の配線確認（任意・Claude Code 抜きで HTTP/SSE が動くか）:

```bash
node -c relay-channel.mjs && echo "syntax OK"
```

---

## 動作確認（ワンコマンド・本物の claude 不要）

リレーの一周（承認要求 → スマホ着信 → yes/no → verdict 返却）を、自分で「Claude Code 役」
と「スマホ役」を演じて検証するハーネスを同梱。**当日 PASS を見せる保険**にも使える:

```bash
cd homework/20260616/claude-code-channels/demo
npm install          # 初回のみ
bash verify.sh
```

末尾に `PASS=4 FAIL=0` が出れば配線 OK（承認プロンプト+ID の着信 / allow / deny /
stderr クリーンを自動判定）。中身と検証範囲は [`verify.sh`](./verify.sh) 冒頭コメント参照。

> これは MCP プロトコル経路の検証。**本物の `claude` がツール承認ダイアログを開いて
> `permission_request` を発火する**ところまで見せたい場合は下の「デモ本番」へ。

---

## デモ本番 — 端末 3 枚

「**スマホ = 端末②の `curl -N`**」というメタファーを最初に宣言してから始めると伝わる。

### 端末①: Claude Code セッション（手元のマシン）

開発フラグ付きで起動する（自作チャネルは research preview の allowlist 外のため）。
起動時に MCP サーバー利用の同意を聞かれたら **Use this MCP server** を選ぶ。

```bash
cd homework/20260616/claude-code-channels/demo
claude --dangerously-load-development-channels server:relay-channel
```

起動バナー下に次の dim な通知が出れば登録成功:

> `Channels (experimental) messages from server:relay-channel inject directly in this session …`

> 「blocked by org policy」と出たら、組織管理者の `channelsEnabled` 有効化が必要。

### 端末②: 「スマホ」= outbound を覗く SSE ストリーム

承認プロンプトと Claude の返信がここにライブで流れてくる。**これを「スマホの画面」**
として観客に見せる。

```bash
curl -N localhost:8788/events
```

→ まず `: connected` が出る。

### 端末③: 「スマホから送る」= chat 投入 と verdict 返信

まず Claude に**承認が要る作業**をさせる。`reply` ツール（チャネルへの返信）には承認が
要るので、Claude が返信しようとした瞬間にリレーが発火する:

```bash
curl -d "echo hello back to me" -H "X-Sender: dev" localhost:8788
```

- 端末①: Claude が読み、`mcp__relay-channel__reply` を呼ぼうとして**承認ダイアログ**が開く。
- 端末②（スマホ）: 一瞬遅れて次が流れてくる ——

  ```
  Claude wants to run mcp__relay-channel__reply: …
  Reply "yes abcde" or "no abcde"
  ```

  ここに出る **5 文字 ID（例 `abcde`）が今日のキモ**。端末①のダイアログにはこの ID は
  出ない＝**リレー経由でしか分からない**。

**スマホ側で承認をタップ**する（②に出た実際の ID に置き換える）:

```bash
curl -d "yes abcde" -H "X-Sender: dev" localhost:8788
```

→ 端末①のダイアログが閉じ、`reply` が実行され、端末②に Claude の返信が届く。
**「スマホで OK したら手元の Claude が動き出した」**が成立。

---

## ここで見せたい「効きどころ」

### 1. 先着優先（ローカルとリモートが両方生きている）

もう一度 `curl -d "echo again" …` で承認待ちにし、**端末②で yes を送る前に端末①の
ダイアログで自分で承認**してみる。リモート側の保留はそのまま破棄される。逆もしかり。
docs の言う *"whichever answer arrives first … the other is dropped"* を体感。

### 2. 拒否もできる

`no abcde` を送ると `behavior: 'deny'` が返り、ツールは拒否される（端末①で No と同じ）。

### 3. セキュリティ — 送信者ゲートが無いと誰でも承認できてしまう

`X-Sender: dev` を**外して**送ると `403 forbidden` で弾かれる:

```bash
curl -d "yes abcde" localhost:8788          # → forbidden
```

このデモサーバは `allowed = new Set(['dev'])` でゲートしている。
docs いわく *「チャネル経由で返信できる人は誰でもツール実行を許可/拒否できる」*ので、
**リレーを宣言するなら送信者の allowlist は必須**。ゲートなしチャネルは
プロンプトインジェクションの経路そのもの、という点を強調する。

### 4. ID が `l` を含まない理由

`request_id` は `a`–`z` から `l` を抜いた 5 文字。**スマホ入力で `1`/`I` と紛れない**ため。
正規表現も `[a-km-z]{5}` で `l` を除外している（`relay-channel.mjs`）。

---

## コードのどこが「リレー」か（端末で開いて見せる用）

`relay-channel.mjs` の 3 点を指させば十分:

| 行 | 役割 |
| --- | --- |
| `'claude/channel/permission': {}` | リレーへのオプトイン宣言（これが無いと 2.1.81+ でも転送されない） |
| `setNotificationHandler(PermissionRequestSchema, …)` | Claude Code からの承認要求を受け、ID 付きプロンプトを `send()` で「スマホ」へ |
| `PERMISSION_REPLY_RE` → `notifications/claude/channel/permission` | `yes/no <id>` を verdict（allow/deny）に変換して Claude Code へ返す |

---

## 検証済みのこと / 当日 Claude Code が要ること

このディレクトリのサーバは、Claude Code 抜きで配線を検証済み:

- `initialize` 応答が `experimental: { "claude/channel": {}, "claude/channel/permission": {} }`
  を広告する（= Claude Code がリレー可能チャネルと認識する）
- `reply` ツール呼び出しが `/events` に SSE 配信される（承認プロンプトと同じ `send()` 経路）
- inbound の chat 転送 / 送信者ゲート(403) / `yes <id>` verdict 解釈 / 形式違いの fall-through

唯一ローカル単体で発火できないのは **Claude Code → サーバーの `permission_request`**
（実際のツール承認ダイアログが開いたときに Claude Code 本体だけが送る）。これは当日
端末①で本物の承認を踏ませて見せる。`permission_request` を受けた後の経路は上の `reply`
ツール検証と同一の `send()` なので、配線は確認済み。

## 後片付け

- 端末①: `/exit`、端末②: `Ctrl-C`。
- ポートが残ったら `pkill -f relay-channel.mjs`。
- `node_modules/` は `.gitignore` 済み（`npm install` で再生成）。

#!/usr/bin/env node
// 権限リレー (permission relay) を最小再現するデモ用チャネルサーバ。
//
// 公式ドキュメント channels-reference.md の "Full webhook.ts with permission relay"
// (Bun 版) を Node.js (node:http) に移植したもの。スマホや Telegram bot を用意せず、
// curl だけで「承認プロンプトを別デバイスに転送 → そこで yes/no を返す」リレーの
// 一周をローカルで体験するためのデモ。
//
//   出典: https://code.claude.com/docs/en/channels-reference.md#relay-permission-prompts
//
// 仕掛けは 3 つ:
//   1. capabilities.experimental に claude/channel と claude/channel/permission を宣言
//      → これで Claude Code が「承認プロンプトをこのチャネルに転送してよい」と判断する。
//   2. notifications/claude/channel/permission_request ハンドラ
//      → Claude Code が承認待ちになると呼ばれる。プロンプトと request_id を /events
//        (SSE) に流す。curl -N で見ている画面が「スマホの通知」に相当。
//   3. inbound (POST /) で "yes <id>" / "no <id>" を検出
//      → notifications/claude/channel/permission verdict を Claude Code に返す。
//        curl で yes を打つのが「スマホで承認をタップ」に相当。
//
// ローカルの terminal ダイアログも開いたままで、先に答えた方 (terminal or リレー) が
// 採用され、もう片方は破棄される。

import http from "node:http";
import { Server } from "@modelcontextprotocol/sdk/server/index.js";
import { StdioServerTransport } from "@modelcontextprotocol/sdk/server/stdio.js";
import {
  ListToolsRequestSchema,
  CallToolRequestSchema,
} from "@modelcontextprotocol/sdk/types.js";
import { z } from "zod";

// --- Outbound: /events を開いている curl -N へ書き出す (= 転送先デバイスの画面) ----
// 実物のブリッジならここで Telegram / Discord 等へ POST する。
const listeners = new Set();
function send(text) {
  const chunk =
    text
      .split("\n")
      .map((l) => `data: ${l}\n`)
      .join("") + "\n";
  for (const res of listeners) res.write(chunk);
}

// 送信者 allowlist。デモでは X-Sender ヘッダの値 "dev" だけ信頼する。
// 実物では platform のユーザ ID を照合する。リレーを宣言するなら必ずゲートを置くこと。
const allowed = new Set(["dev"]);

const mcp = new Server(
  { name: "relay-channel", version: "0.0.1" },
  {
    capabilities: {
      experimental: {
        "claude/channel": {}, // チャネルのリスナを登録
        "claude/channel/permission": {}, // 権限リレーにオプトイン (← 今日の主役)
      },
      tools: {},
    },
    instructions:
      'Messages arrive as <channel source="relay-channel" chat_id="...">. ' +
      "Reply with the reply tool, passing the chat_id from the tag.",
  },
);

// --- reply tool: Claude が応答を返すときに呼ぶ (= 2-way チャネル) ----------------
mcp.setRequestHandler(ListToolsRequestSchema, async () => ({
  tools: [
    {
      name: "reply",
      description: "Send a message back over this channel",
      inputSchema: {
        type: "object",
        properties: {
          chat_id: { type: "string", description: "The conversation to reply in" },
          text: { type: "string", description: "The message to send" },
        },
        required: ["chat_id", "text"],
      },
    },
  ],
}));

mcp.setRequestHandler(CallToolRequestSchema, async (req) => {
  if (req.params.name === "reply") {
    const { chat_id, text } = req.params.arguments;
    send(`Reply to ${chat_id}: ${text}`);
    return { content: [{ type: "text", text: "sent" }] };
  }
  throw new Error(`unknown tool: ${req.params.name}`);
});

// --- permission relay: 承認ダイアログが開くと Claude Code (Claude ではない) が呼ぶ ---
const PermissionRequestSchema = z.object({
  method: z.literal("notifications/claude/channel/permission_request"),
  params: z.object({
    request_id: z.string(), // 小文字 5 文字 (l を除く)。プロンプトにそのまま載せる
    tool_name: z.string(), // 例 "Bash", "Write"
    description: z.string(), // この呼び出しが何をするかの人間向け要約
    input_preview: z.string(), // ツール引数の JSON (200 文字に切り詰め)
  }),
});

mcp.setNotificationHandler(PermissionRequestSchema, async ({ params }) => {
  send(
    `Claude wants to run ${params.tool_name}: ${params.description}\n` +
      `  ${params.input_preview}\n\n` +
      // ここに載せた id を inbound 側の正規表現で拾う
      `Reply "yes ${params.request_id}" or "no ${params.request_id}"`,
  );
});

await mcp.connect(new StdioServerTransport());

// --- HTTP :8788 ---------------------------------------------------------------
//   GET /events  : SSE。outbound (reply / 承認プロンプト) を curl -N で観測する用
//   POST /       : inbound。X-Sender でゲートし、verdict 形式なら承認、それ以外は chat
// "y abcde" / "yes abcde" / "n abcde" / "no abcde" にマッチ。
//   [a-km-z] = Claude Code の id 文字集合 (小文字, l を飛ばす)
//   /i はスマホの autocorrect 大文字化を許容。送り返す前に小文字化する。
const PERMISSION_REPLY_RE = /^\s*(y|yes|n|no)\s+([a-km-z]{5})\s*$/i;
let nextId = 1;

function readBody(req) {
  return new Promise((resolve) => {
    let data = "";
    req.on("data", (c) => (data += c));
    req.on("end", () => resolve(data));
  });
}

const server = http.createServer(async (req, res) => {
  const url = new URL(req.url, "http://localhost");

  // GET /events: SSE ストリームを開きっぱなしにして outbound をライブ表示
  if (req.method === "GET" && url.pathname === "/events") {
    res.writeHead(200, {
      "Content-Type": "text/event-stream",
      "Cache-Control": "no-cache",
      Connection: "keep-alive",
    });
    res.write(": connected\n\n"); // curl にすぐ何か出す
    listeners.add(res);
    req.on("close", () => listeners.delete(res));
    return;
  }

  // それ以外は inbound: まず送信者をゲート
  const body = await readBody(req);
  const sender = req.headers["x-sender"] ?? "";
  if (!allowed.has(sender)) {
    res.writeHead(403);
    res.end("forbidden");
    return;
  }

  // chat として扱う前に verdict 形式かどうか確認
  const m = PERMISSION_REPLY_RE.exec(body);
  if (m) {
    await mcp.notification({
      method: "notifications/claude/channel/permission",
      params: {
        request_id: m[2].toLowerCase(), // autocorrect 大文字化に備えて正規化
        behavior: m[1].toLowerCase().startsWith("y") ? "allow" : "deny",
      },
    });
    res.writeHead(200);
    res.end("verdict recorded");
    return;
  }

  // 通常の chat: channel イベントとして Claude に転送
  const chat_id = String(nextId++);
  await mcp.notification({
    method: "notifications/claude/channel",
    params: { content: body, meta: { chat_id, path: url.pathname } },
  });
  res.writeHead(200);
  res.end("ok");
});

server.listen(8788, "127.0.0.1");

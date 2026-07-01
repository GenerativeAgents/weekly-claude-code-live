#!/usr/bin/env node
// deep-link-register.mjs
// -----------------------------------------------------------------------------
// Claude Code の "claude-cli:// プロトコルハンドラ登録" と、それを止める
// `disableDeepLinkRegistration` 設定の Node 移植（Linux 版）。
//
// ローカルにインストール済みの Claude Code v2.1.197 バイナリから、登録まわりの
// 関数を逆アセンブルして忠実に再現した。元の内部シンボルとの対応:
//   register()        <- uEf(e)     : .desktop 書き込み + xdg-mime default
//   isRegistered()    <- mEf(e)     : 既に自分の Exec 行があるか（冪等チェック）
//   autoRegister()    <- dCc()      : 設定ゲート → platform → 冪等 → register
//   desktopFilePath() <- Kmr()/Soe(): $XDG_DATA_HOME/applications/<file>
//   execLine()        <- lCc(e)     : 'Exec="<path>" --handle-uri %u'
//
// 受信側（URL パース・検証・引数ガード）は本物の `claude --handle-uri` が headless
// でも動くので、そちらは verify.sh で実バイナリを直接叩いて確認する。ここは、実機
// では GUI/デスクトップ環境が要って見せにくい「登録の副作用」を、設定の on/off で
// 決定的に再現するためのもの。
// -----------------------------------------------------------------------------
import { promises as fs } from "node:fs";
import { existsSync } from "node:fs";
import path from "node:path";
import os from "node:os";
import { execFileSync } from "node:child_process";

// バイナリ実測の定数
export const SCHEME = "claude-cli";                          // P5
export const DESKTOP_FILE = "claude-code-url-handler.desktop"; // iCc
const MIME = `x-scheme-handler/${SCHEME}`;

// Soe(): データディレクトリ。XDG_DATA_HOME ?? ~/.local/share
function dataHome(env = process.env) {
  return env.XDG_DATA_HOME ?? path.join(os.homedir(), ".local", "share");
}

// Kmr(): 書き込み先の .desktop フルパス
export function desktopFilePath(env = process.env) {
  return path.join(dataHome(env), "applications", DESKTOP_FILE);
}

// lCc(e): Exec 行
function execLine(execPath) {
  return `Exec="${execPath}" --handle-uri %u`;
}

// uEf() が書く .desktop の中身（実物とバイト単位で一致するテンプレート）
export function desktopContents(execPath) {
  return [
    "[Desktop Entry]",
    "Name=Claude Code URL Handler",
    "Comment=Handle claude-cli:// deep links for Claude Code",
    execLine(execPath),
    "Type=Application",
    "NoDisplay=true",
    `MimeType=${MIME};`,
    "",
  ].join("\n");
}

// uCc(): ハンドラが起動する実行ファイル。~/.local/bin/claude を優先、無ければ argv/execPath
export function resolveExecPath(env = process.env) {
  const local = path.join(os.homedir(), ".local", "bin", "claude");
  if (existsSync(local)) return local;
  return process.execPath;
}

// mEf(e) linux: 既に自分の Exec 行を含む .desktop があるか
export async function isRegistered(execPath, env = process.env) {
  try {
    const body = await fs.readFile(desktopFilePath(env), "utf8");
    return body.includes(execLine(execPath));
  } catch {
    return false;
  }
}

// uEf(e): .desktop を書き、xdg-mime があれば default 関連付けまでやる（ベストエフォート）
export async function register(execPath, env = process.env) {
  const file = desktopFilePath(env);
  await fs.mkdir(path.dirname(file), { recursive: true });
  await fs.writeFile(file, desktopContents(execPath));
  let mimeAssociated = false;
  try {
    execFileSync("xdg-mime", ["default", DESKTOP_FILE, MIME], { stdio: "ignore" });
    mimeAssociated = true;
  } catch {
    // xdg-mime 不在 or 失敗。ファイルは書けているので "半分登録" 状態（headless で普通に起きる）
  }
  return { file, mimeAssociated };
}

// dCc(): 起動時の自動登録。ここに `disableDeepLinkRegistration` ゲートが入る。
export async function autoRegister({ settings = {}, execPath, env = process.env } = {}) {
  // ★ これが今回のチェンジログ行の本体 ★
  if (settings.disableDeepLinkRegistration === "disable") {
    return { action: "skipped", reason: "disableDeepLinkRegistration" };
  }
  if (!["darwin", "linux", "win32"].includes(process.platform)) {
    return { action: "skipped", reason: "unsupported-platform" };
  }
  const exe = execPath ?? resolveExecPath(env);
  if (await isRegistered(exe, env)) {
    return { action: "already-registered", file: desktopFilePath(env) };
  }
  const res = await register(exe, env);
  return { action: "registered", ...res };
}

// --- 参考: 受信側の忠実移植（本番は実 claude を使うが、対照用に同梱） -------------

// oCc(e): claude-cli:// URL をアクションにパース。host は "open" のみ、q<=5000 等。
export function parseDeepLink(uri) {
  let t = uri.startsWith(`${SCHEME}://`)
    ? uri
    : uri.startsWith(`${SCHEME}:`)
    ? uri.replace(`${SCHEME}:`, `${SCHEME}://`)
    : null;
  if (!t) throw new Error(`Invalid deep link: expected ${SCHEME}:// scheme, got "${uri}"`);
  let url;
  try {
    url = new URL(t);
  } catch {
    throw new Error(`Invalid deep link URL: "${uri}"`);
  }
  if (url.hostname !== "open") throw new Error(`Unknown deep link action: "${url.hostname}"`);
  const cwd = url.searchParams.get("cwd") ?? undefined;
  const repo = url.searchParams.get("repo") ?? undefined;
  const q = url.searchParams.get("q");
  if (cwd) {
    if (cwd.startsWith("//") || cwd.startsWith("\\\\"))
      throw new Error(`Invalid cwd in deep link: UNC / network paths are not supported, got "${cwd}"`);
    if (/[\u0000-\u001f\u007f-\u009f\u00a0\u200b-\u200f\u202a-\u202e\u2066-\u2069]/.test(cwd))
      throw new Error(`Deep link cwd contains invisible or bidirectional control characters`);
  }
  if (repo && !/^[\w.-]+\/[\w.-]+$/.test(repo))
    throw new Error(`Invalid repo in deep link: expected "owner/repo", got "${repo}"`);
  let query;
  if (q && q.trim().length > 0) {
    if (q.length > 5000) throw new Error(`Deep link query exceeds 5000 characters (got ${q.length})`);
    query = q.trim();
  }
  return { query, cwd, repo };
}

// Dsn(argv): OS ハンドラは厳密に `--handle-uri <uri>` だけを渡す。後ろに余分な引数が
// あれば引数インジェクションとして拒否。
export function guardHandleUri(argv) {
  const i = argv.indexOf("--handle-uri");
  if (i === -1 || !argv[i + 1]) return null;
  if (argv.length > i + 2)
    return "claude: rejected deep-link invocation — unexpected arguments after the URI.";
  return { ok: true, uri: argv[i + 1] };
}

// --- 小さな CLI（当日ライブで叩く用） ----------------------------------------
if (import.meta.url === `file://${process.argv[1]}`) {
  const [cmd, ...rest] = process.argv.slice(2);
  const run = async () => {
    switch (cmd) {
      case "auto-register": {
        // rest[0] があれば settings.json のパス
        let settings = {};
        if (rest[0]) settings = JSON.parse(await fs.readFile(rest[0], "utf8"));
        const res = await autoRegister({ settings, execPath: resolveExecPath() });
        console.log(JSON.stringify(res, null, 2));
        break;
      }
      case "show-desktop":
        process.stdout.write(desktopContents(resolveExecPath()));
        break;
      case "path":
        console.log(desktopFilePath());
        break;
      case "parse":
        console.log(JSON.stringify(parseDeepLink(rest[0]), null, 2));
        break;
      default:
        console.log(
          "usage: node deep-link-register.mjs <auto-register [settings.json] | show-desktop | path | parse <uri>>"
        );
    }
  };
  run().catch((e) => {
    console.error(String(e.message ?? e));
    process.exit(1);
  });
}

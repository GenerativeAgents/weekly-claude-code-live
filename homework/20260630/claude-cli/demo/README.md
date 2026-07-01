# `disableDeepLinkRegistration` / `claude-cli://` デモ手順

changelog の主役は **「`claude-cli://` プロトコルハンドラの OS 登録を止める設定
`disableDeepLinkRegistration` を追加した」**。

このデモは 2 系統に分けて見せる。**依存パッケージなし**（純 Node + 実 `claude`）:

| 系統 | 何を | どう見せる |
| --- | --- | --- |
| **受信側** | `claude-cli://…` を **実 claude がパース・検証・拒否** | `claude --handle-uri` を直接叩く（headless で動く） |
| **登録側** | 設定が **OS 登録の副作用を on/off** する | 公式ロジックの Node 移植 `deep-link-register.mjs` をサンドボックスに対して実行 |

デモ用語: **「リンクをクリック」= OS が `claude --handle-uri <uri>` を起動すること**。
このコンテナには GUI もデスクトップ環境も無いので、その「OS が起動する」1 手だけを
自分の手で `claude --handle-uri …` と打って代行する。それ以外は全部本物。

前回踏襲で、**このディレクトリに `cd` してから**実行する。

---

## 前提

- **Claude Code v2.1.91+**（deep link 機能）。`disableDeepLinkRegistration` はそれ以降
- **Node.js**（`node --version`。追加パッケージ不要）
- 受信側テストは **実 `claude`** を使う（`command -v claude`）
- 登録の**完全な**実演（クリック → 新端末が開く）は**デスクトップ環境が要る**ので、
  このコンテナでは「端末が無い」ところまで。フルは実マシンで

## 事前準備

```bash
cd homework/20260630/claude-cli/demo
node --version && claude --version
```

このマシンには過去の対話起動で書かれた**実物のハンドラ**が既にある（あれば）:

```bash
cat ~/.local/share/applications/claude-code-url-handler.desktop
```

```ini
[Desktop Entry]
Name=Claude Code URL Handler
Comment=Handle claude-cli:// deep links for Claude Code
Exec="/home/vscode/.local/bin/claude" --handle-uri %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/claude-cli;
```

> `Exec=… --handle-uri %u` が肝。OS はクリックされた URL を `%u` に入れて claude を叩く。
> ただしこのコンテナには `xdg-mime` が無いので mime 関連付けは未完（＝
> `xdg-mime query default x-scheme-handler/claude-cli` は空）。「登録はベストエフォート」の実例。

---

## 動作確認（ワンコマンド・PASS を見せる保険）

```bash
cd homework/20260630/claude-cli/demo
bash verify.sh
```

末尾に **`PASS=12 FAIL=0`** が出れば配線 OK。内訳:

- 登録側（移植版）: 移植 .desktop が実物とバイト一致 / 設定なし→登録 / 冪等 /
  `"disable"`→登録スキップ
- 受信側（実 claude）: 正常リンクのパース / 引数インジェクション拒否 / 未知アクション拒否 /
  不正 repo・q>5000・UNC・bidi 制御文字・非スキーム の各拒否

---

## デモ本番①: 受信側 — 実 claude にリンクを処理させる

「**クリック = OS が `claude --handle-uri <uri>` を起動**」を宣言してから始める。

### 正常なリンク（パースは通る）

```bash
claude --handle-uri "claude-cli://open?cwd=$PWD&q=review%20open%20PRs"
```

→ このコンテナでは端末が無いので:

```
Failed to open a terminal. Make sure a supported terminal emulator is installed.
```

**パースは成功していて、あとは端末を開くだけ**の状態。実マシンなら新しいターミナルが開き、
`cwd` で Claude が起動し、プロンプト欄に `review open PRs` が**入力済み**で待つ（Enter まで送信されない）。

### ここが今日のセキュリティの見どころ

deep link は「外部 → 手元 CLI」の入口なので、受信側は固い。全部**実 claude の出力**:

```bash
# 1) 引数インジェクション防御: URI の後ろに余分な引数を足すと即拒否
claude --handle-uri "claude-cli://open?q=hello" EXTRA-ARG
#   → claude: rejected deep-link invocation — unexpected arguments after the URI.

# 2) アクションは open のみ
claude --handle-uri "claude-cli://danger?q=x"
#   → Deep link error: Unknown deep link action: "danger"

# 3) repo は owner/name 形式
claude --handle-uri "claude-cli://open?repo=notaslug&q=x"
#   → Deep link error: Invalid repo in deep link: expected "owner/repo", got "notaslug"

# 4) cwd の UNC/ネットワークパス拒否
claude --handle-uri 'claude-cli://open?cwd=//server/share&q=x'
#   → Deep link error: Invalid cwd in deep link: UNC / network paths are not supported

# 5) cwd に双方向/不可視制御文字（%E2%80%AE = U+202E）を仕込むと拒否
claude --handle-uri "claude-cli://open?cwd=%2Ftmp%2F%E2%80%AEevil&q=x"
#   → Deep link error: Deep link cwd contains invisible or bidirectional control characters

# 6) そもそも claude-cli:// 以外は拒否
claude --handle-uri "https://evil.example/pwn"
#   → Deep link error: Invalid deep link: expected claude-cli:// scheme
```

**プロンプトは入力されるだけで送信されない**（inert）／**引数は URI 1 個だけ**／**cwd と repo は
サニタイズ**、の 3 点が deep link の安全弁。

---

## デモ本番②: 登録側 — 設定が OS 登録を on/off する

実 claude の登録は「初回の対話起動時」にしか走らず headless で見せにくいので、**公式ロジックを
そのまま移植した** `deep-link-register.mjs`（内部関数 `dCc`/`uEf`/`mEf` 相当）で再現する。
移植版が吐く `.desktop` は実物とバイト一致（verify.sh T0 で保証済み）。

### 設定なし → 登録される

```bash
SB=$(mktemp -d)
XDG_DATA_HOME=$SB node deep-link-register.mjs auto-register settings/with-registration.json
#   → {"action":"registered", ...}
cat "$SB/applications/claude-code-url-handler.desktop"   # 実物と同じ内容が書かれている
```

### もう一度 → 冪等（already-registered、書き換えない）

```bash
XDG_DATA_HOME=$SB node deep-link-register.mjs auto-register settings/with-registration.json
#   → {"action":"already-registered", ...}
rm -rf "$SB"
```

### `disableDeepLinkRegistration: "disable"` → 登録しない

```bash
SB=$(mktemp -d)
XDG_DATA_HOME=$SB node deep-link-register.mjs auto-register settings/disabled.json
#   → {"action":"skipped","reason":"disableDeepLinkRegistration"}
ls "$SB/applications" 2>&1        # → No such file or directory（applications すら作らない）
rm -rf "$SB"
```

`settings/disabled.json` の中身が今日の設定そのもの:

```json
{ "disableDeepLinkRegistration": "disable" }
```

---

## 効きどころ（3 行で）

1. **`disableDeepLinkRegistration: "disable"` は起動時の OS 登録を丸ごとスキップする**
   （値は `"disable"` の一択。boolean ではない）。
2. **止めるのは「登録」であって「機能」ではない**。既に登録済みの `.desktop` / `.app` /
   レジストリはこの設定では消えない。完全に断つなら既存実体も手で削除する。
3. **受信側は多層で固い**: プロンプト inert・引数インジェクション拒否・`open` のみ・
   cwd/repo サニタイズ・q 5000 文字上限。全部このデモで実 claude が実演する。

## コードのどこが要点か（開いて指させる用）

`deep-link-register.mjs`:

| 場所 | 役割 |
| --- | --- |
| `autoRegister()` 冒頭の `settings.disableDeepLinkRegistration === "disable"` で return | **今日の設定の本体**。ここで登録を打ち切る |
| `desktopContents()` の `Exec="…" --handle-uri %u` | OS がクリック時に叩くコマンド。実物とバイト一致 |
| `register()` の `xdg-mime default …`（ベストエフォート） | mime 関連付け。無ければ "半分登録" になる |
| `parseDeepLink()` / `guardHandleUri()` | 受信側の対照実装（本番は実 claude を使う） |

## 後片付け

- サンドボックスは `mktemp -d`（/tmp 側）なので `rm -rf "$SB"` で消える。取り残しは
  `rm -rf /tmp/tmp.*/applications` 等で。
- **このマシンの実物**は消していない（`~/.local/share/applications/claude-code-url-handler.desktop`）。
  実際に外したい場合は `rm ~/.local/share/applications/claude-code-url-handler.desktop`。

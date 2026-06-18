#!/usr/bin/env bash
# 権限リレー (--channels) の一周を、本物の Claude Code 抜きで検証するワンコマンド・ハーネス。
#
#   実行:  bash verify.sh        (このディレクトリで)
#
# このスクリプト自身が「Claude Code 役」を stdio で、「スマホ役」を curl で演じる:
#   A. Claude Code 役 → サーバへ permission_request(id=abcde, Bash) を送る
#   B. スマホ役が /events で承認プロンプト + ID を受け取る
#   C. スマホ役が "yes abcde" を返す（承認タップ相当）
#   D. サーバが Claude Code 役へ verdict {behavior:"allow"} を返す
# さらに 送信者ゲート(403) / deny / 形式違い fall-through も確認する。
#
# 本物の claude を使ったライブ手順は README.md を参照。
set -u
DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
cd "$DIR" || exit 1

if [ ! -d node_modules ]; then
  echo "node_modules がありません。先に: npm install" >&2
  exit 2
fi

pkill -f relay-channel.mjs 2>/dev/null
rm -f /tmp/relay.stdout /tmp/relay.stderr /tmp/events.out /tmp/relay_stdin
mkfifo /tmp/relay_stdin

# サーバ起動（stdin=FIFO で保持、stdout=Claude Code 向け JSON-RPC を捕捉）
node ./relay-channel.mjs < /tmp/relay_stdin > /tmp/relay.stdout 2> /tmp/relay.stderr &
exec 4> /tmp/relay_stdin

# ポート待ち
for i in $(seq 1 25); do (exec 3<>/dev/tcp/127.0.0.1/8788) 2>/dev/null && { exec 3>&-; break; }; sleep 0.2; done

# 1) MCP ハンドシェイク（Claude Code 役）
printf '%s\n' '{"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2024-11-05","capabilities":{},"clientInfo":{"name":"claude-code-sim","version":"0"}}}' >&4
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/initialized"}' >&4
sleep 0.6

# 2) スマホ役: /events を購読
curl -sN http://localhost:8788/events > /tmp/events.out 2>/dev/null &
CURL=$!
sleep 0.5

echo "================ STEP A: Claude Code が承認要求を送る ================"
echo ">> notifications/claude/channel/permission_request (request_id=abcde, tool=Bash)"
printf '%s\n' '{"jsonrpc":"2.0","method":"notifications/claude/channel/permission_request","params":{"request_id":"abcde","tool_name":"Bash","description":"echo hi","input_preview":"{\"command\":\"echo hi\"}"}}' >&4
sleep 0.8
echo
echo "================ STEP B: スマホ(/events)に届いたプロンプト ================"
cat /tmp/events.out
echo
echo "================ STEP C: スマホから承認をタップ (yes abcde) ================"
echo ">> POST 'yes abcde' (X-Sender: dev) -> server: $(curl -s -d 'yes abcde' -H 'X-Sender: dev' http://localhost:8788/)"
sleep 0.8
echo
echo "================ STEP D: サーバが Claude Code へ返した verdict ================"
grep -o '"method":"notifications/claude/channel/permission","params":{[^}]*}' /tmp/relay.stdout | head -1
echo
echo "================ 追加検証: 送信者ゲート / deny / 形式違い ================"
echo -n "[gate] X-Sender 無しで 'yes abcde' -> "; curl -s -o /tmp/b -w "%{http_code} " -d "yes abcde" http://localhost:8788/; cat /tmp/b; echo
echo -n "[deny] 'no abcde' (dev) -> "; curl -s -d "no abcde" -H "X-Sender: dev" http://localhost:8788/; echo
echo -n "[chat] 'approve it'(形式違い, dev) -> "; curl -s -d "approve it" -H "X-Sender: dev" http://localhost:8788/; echo
sleep 0.5
echo
echo "================ PASS/FAIL 判定 ================"
PASS=0; FAIL=0
grep -q 'Reply "yes abcde"' /tmp/events.out && { echo "[OK] 承認プロンプト+ID がスマホ(/events)に届いた"; PASS=$((PASS+1)); } || { echo "[NG] プロンプトが /events に出ていない"; FAIL=$((FAIL+1)); }
grep -q '"request_id":"abcde","behavior":"allow"' /tmp/relay.stdout && { echo "[OK] yes -> behavior:allow を Claude Code へ返した"; PASS=$((PASS+1)); } || { echo "[NG] allow verdict が出ていない"; FAIL=$((FAIL+1)); }
grep -q '"request_id":"abcde","behavior":"deny"' /tmp/relay.stdout && { echo "[OK] no -> behavior:deny を返した"; PASS=$((PASS+1)); } || { echo "[NG] deny verdict が出ていない"; FAIL=$((FAIL+1)); }
[ -s /tmp/relay.stderr ] && { echo "[NG] stderr に出力あり:"; cat /tmp/relay.stderr; FAIL=$((FAIL+1)); } || { echo "[OK] stderr クリーン"; PASS=$((PASS+1)); }
echo "PASS=$PASS FAIL=$FAIL"

# 後片付け
exec 4>&-
kill "$CURL" 2>/dev/null; pkill -f relay-channel.mjs 2>/dev/null
rm -f /tmp/relay_stdin /tmp/b
exit "$FAIL"

#!/usr/bin/env bash
# verify.sh — claude-cli:// ディープリンクと disableDeepLinkRegistration の配線検証
# -----------------------------------------------------------------------------
# 2 系統をまとめて PASS/FAIL 判定する:
#
#   [受信側] 本物の `claude --handle-uri <uri>` を直接叩く。パース・検証・拒否・
#            引数インジェクション防御は headless でも実バイナリで走るので、ここは
#            "本物の claude の挙動" をそのまま assert する。
#
#   [登録側] deep-link-register.mjs（公式ロジックの Node 移植）をサンドボックスの
#            XDG_DATA_HOME に対して走らせ、"設定なし → 登録される" / "disable →
#            登録されない" / "冪等" を決定的に確認する。実 claude の登録は対話起動時に
#            しか走らず headless では見せにくいので、ここは移植版で代替する
#            （移植版の .desktop は実物とバイト一致することを T0 で保証）。
#
# 使い方: このディレクトリに cd してから  bash verify.sh
# -----------------------------------------------------------------------------
set -u
cd "$(dirname "$0")"

PASS=0; FAIL=0
ok(){ PASS=$((PASS+1)); printf '  \033[32mPASS\033[0m %s\n' "$1"; }
ng(){ FAIL=$((FAIL+1)); printf '  \033[31mFAIL\033[0m %s\n' "$1"; [ -n "${2:-}" ] && printf '       %s\n' "$2"; }
# check "名前" "期待部分文字列" -- コマンド...   ( stdout+stderr に部分文字列を含めば PASS )
check(){ local name="$1" want="$2"; shift 3; local out; out="$("$@" 2>&1)";
  case "$out" in *"$want"*) ok "$name";; *) ng "$name" "want «$want», got «$(printf '%s' "$out" | head -1)»";; esac; }

MJS="deep-link-register.mjs"
REAL_DESKTOP="$HOME/.local/share/applications/claude-code-url-handler.desktop"

echo "== 登録側: 移植版 deep-link-register.mjs =="

# T0: 移植版が生成する .desktop が、このマシンに実在する実物とバイト一致するか
if [ -f "$REAL_DESKTOP" ]; then
  if diff -q <(node "$MJS" show-desktop) "$REAL_DESKTOP" >/dev/null 2>&1; then
    ok "T0 移植版の .desktop が実物（$REAL_DESKTOP）とバイト一致"
  else
    ng "T0 移植版の .desktop が実物と不一致"
  fi
else
  ok "T0 実物 .desktop 無し（このマシンでは未登録）— 移植版の生成のみ確認"
  node "$MJS" show-desktop >/dev/null && ok "T0b show-desktop が生成できる"
fi

# T1: 設定なし → サンドボックスに登録される（.desktop が書かれ、Exec 行が入る）
SB="$(mktemp -d)"
R1="$(XDG_DATA_HOME="$SB" node -e 'import("./'"$MJS"'").then(async m=>{const r=await m.autoRegister({settings:{},env:process.env,execPath:m.resolveExecPath()});console.log(r.action)})')"
DESK="$SB/applications/claude-code-url-handler.desktop"
[ "$R1" = "registered" ] && [ -f "$DESK" ] && grep -q -- '--handle-uri %u' "$DESK" \
  && ok "T1 設定なし → registered（.desktop に Exec … --handle-uri %u）" \
  || ng "T1 設定なしで登録されなかった" "action=$R1 file=$([ -f "$DESK" ] && echo yes || echo no)"

# T2: 冪等 — もう一度呼んでも already-registered で書き換えない
BEFORE="$(stat -c %Y "$DESK" 2>/dev/null || echo 0)"
sleep 1
R2="$(XDG_DATA_HOME="$SB" node -e 'import("./'"$MJS"'").then(async m=>{const r=await m.autoRegister({settings:{},env:process.env,execPath:m.resolveExecPath()});console.log(r.action)})')"
AFTER="$(stat -c %Y "$DESK" 2>/dev/null || echo 0)"
[ "$R2" = "already-registered" ] && [ "$BEFORE" = "$AFTER" ] \
  && ok "T2 冪等（already-registered・再書き込みなし）" \
  || ng "T2 冪等でない" "action=$R2 mtime $BEFORE→$AFTER"
rm -rf "$SB"

# T3: disableDeepLinkRegistration=disable → まっさらなサンドボックスに何も書かない
SB2="$(mktemp -d)"
R3="$(XDG_DATA_HOME="$SB2" node -e 'import("./'"$MJS"'").then(async m=>{const r=await m.autoRegister({settings:{disableDeepLinkRegistration:"disable"},env:process.env});console.log(r.action)})')"
[ "$R3" = "skipped" ] && [ ! -e "$SB2/applications" ] \
  && ok 'T3 "disable" → skipped（applications ディレクトリすら作らない）' \
  || ng "T3 disable なのに登録された" "action=$R3"
rm -rf "$SB2"

echo ""
echo "== 受信側: 本物の claude --handle-uri =="
if ! command -v claude >/dev/null 2>&1; then
  ng "claude 実バイナリが見つからない（受信側テストをスキップ）"
else
  cl(){ timeout 30 claude --handle-uri "$@"; }
  BIG="$(printf 'a%.0s' $(seq 1 5001))"
  # 正常なリンク: パースは通り、端末が無いので "Failed to open a terminal"
  check "R1 正常 open リンク → パース成功・端末起動を試みる" "Failed to open a terminal" \
    -- cl "claude-cli://open?cwd=$PWD&q=review%20open%20PRs"
  # 引数インジェクション防御: URI の後ろに余分な引数
  check "R2 引数インジェクション拒否（余分な引数）" "rejected deep-link invocation" \
    -- cl "claude-cli://open?q=hello" EXTRA-ARG
  # アクションは open のみ
  check "R3 未知アクション拒否" 'Unknown deep link action: "danger"' \
    -- cl "claude-cli://danger?q=x"
  # repo は owner/name
  check "R4 不正 repo 拒否" 'expected "owner/repo"' \
    -- cl "claude-cli://open?repo=notaslug&q=x"
  # q は 5000 文字上限
  check "R5 q>5000 文字拒否" "exceeds 5000 characters" \
    -- cl "claude-cli://open?q=$BIG"
  # cwd の UNC/ネットワークパス拒否
  check "R6 UNC/network cwd 拒否" "UNC / network paths are not supported" \
    -- cl 'claude-cli://open?cwd=//server/share&q=x'
  # cwd の双方向/不可視制御文字拒否（%E2%80%AE = U+202E）
  check "R7 bidi/制御文字 cwd 拒否" "invisible or bidirectional control characters" \
    -- cl "claude-cli://open?cwd=%2Ftmp%2F%E2%80%AEevil&q=x"
  # claude-cli:// 以外のスキーム拒否
  check "R8 非 claude-cli スキーム拒否" "expected claude-cli:// scheme" \
    -- cl "https://evil.example/pwn"
fi

echo ""
printf 'PASS=%d FAIL=%d\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]

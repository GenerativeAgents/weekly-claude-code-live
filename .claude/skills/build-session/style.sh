#!/usr/bin/env bash
# build-session の見た目ヘルパ。`source style.sh` して build_card / build_demo / concat_session を使う。
# 全セグメントを 1280x720・同一コーデックで作るので、最後の連結は -c copy で通る。
# 依存: ffmpeg/ffprobe, asciinema, agg, edge-tts, Noto Sans CJK JP, Fira Code。
export PATH="$HOME/.local/bin:$PATH" TERM=xterm-256color

: "${NOTO:=$(fc-list | grep -i notosanscjk | grep -i regular | head -1 | sed 's/:.*//')}"
: "${FIRA:=$(fc-list | grep -i firacode | grep -iE 'semibold|bold' | head -1 | sed 's/:.*//')}"
# 太字（表紙タイトル用。Noto Sans Bold のラテン）
: "${BOLD:=$(fc-list | grep -i notosanscjk | grep -i bold | head -1 | sed 's/:.*//')}"
# agg カスタム暖色テーマ: 背景をパネル色 #0f0d0a に一致させ、端末をウィンドウ枠に溶け込ませる
: "${THEME:=0f0d0a,ede8df,0f0d0a,e06c5a,8fa96a,e0a24e,c99a6b,c77da0,7aa89f,c9c0b0,5a544a,e88d7d,a8c288,eab973,d9b48a,d69cbd,9ac7bd,ede8df}"

# edge-tts は連続呼び出しで時々ネットワーク失敗するのでリトライ包む。引数: outfile text
tts() {
  local out="$1" text="$2" i
  for i in 1 2 3 4; do
    edge-tts --voice ja-JP-NanamiNeural --text "$text" --write-media "$out" 2>/dev/null \
      && [ -s "$out" ] && return 0
    timeout 2 tail -f /dev/null 2>/dev/null
  done
  return 1
}

CORAL=0xD97757; CREAM=0xEDE8DF; MUTE=0x9A9184; SUBC=0xE8A87C
PANEL=0x0F0D0A; PBORDER=0x3A332A; TBAR=0x241E17; CAPC=0xB8AE9E
DOTR=0xE06C5A; DOTY=0xE0A24E; DOTG=0x8FA96A
TITLEC=0xDD6A47   # 表紙タイトルのコーラル（connpass サムネ寄りに彩度アップ）
GRAD="gradients=s=1280x720:c0=0x1E1913:c1=0x0E0B08:x0=0:y0=0:x1=1280:y1=720:n=2:speed=0.00001"

# 表紙タイトル（イベント名）。既定は 3 行。上書き可。
: "${COVER_L1:=Weekly}"; : "${COVER_L2:=Claude Code}"; : "${COVER_L3:=Live}"

# 上下のヘッダー/フッター帯（版と進捗）。引数: ver prog
hf() {
  printf "%s" "\
drawbox=x=0:y=70:w=1280:h=2:color=${CORAL}@0.30:t=fill,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${CORAL}:fontsize=20:x=56:y=25,\
drawtext=fontfile=${NOTO}:text='Weekly Claude Code Live':fontcolor=${CREAM}:fontsize=23:x=88:y=26,\
drawbox=x=0:y=648:w=1280:h=2:color=${CORAL}@0.30:t=fill,\
drawtext=fontfile=${NOTO}:text='${1}':fontcolor=${MUTE}:fontsize=22:x=56:y=676,\
drawtext=fontfile=${NOTO}:text='${2}':fontcolor=${MUTE}:fontsize=22:x=w-tw-56:y=676"
}

# カード（デモ無し）。引数: dir bigfont bigtext bigsize subtitle footerver prog
# bigfont は "$FIRA"（版番号）か "$NOTO"（日本語タイトル）。narration.mp3 は事前に用意しておく。
build_card() {
  local dir="$1" bf="$2" big="$3" bsize="$4" sub="$5" ver="$6" prog="$7"
  local dur; dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/narration.mp3")
  local ulw=110 ulx suby=392; ulx=$(( (1280-ulw)/2 ))
  ffmpeg -y -f lavfi -i "$GRAD" -i "$dir/narration.mp3" -t "$dur" -vf "\
$(hf "$ver" "$prog"),\
drawtext=fontfile=${bf}:text='${big}':fontcolor=${CREAM}:fontsize=${bsize}:x=(w-tw)/2:y=250,\
drawbox=x=${ulx}:y=${suby}:w=${ulw}:h=5:color=${CORAL}:t=fill,\
drawtext=fontfile=${NOTO}:text='${sub}':fontcolor=${SUBC}:fontsize=36:x=(w-tw)/2:y=$((suby+38))" \
    -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$dir/card.mp4"
}

# 録画済み demo.cast → スタイル付き demo.mp4。引数: dir caption footerver prog [fontsize]
# 通常デモ（build_demo）からも、対話TUIの録画（下記「対話TUI」）からも共通で使う描画部。
render_demo() {
  local dir="$1" cap="$2" ver="$3" prog="$4" fs="${5:-22}"
  agg --theme "$THEME" --font-family "Fira Code" --font-size "$fs" "$dir/demo.cast" "$dir/term.gif" || return 1
  ffmpeg -y -f lavfi -i "$GRAD" -frames:v 1 -vf "\
$(hf "$ver" "$prog"),\
drawbox=x=90:y=112:w=1100:h=468:color=${PANEL}:t=fill,\
drawbox=x=90:y=112:w=1100:h=468:color=${PBORDER}:t=2,\
drawbox=x=90:y=112:w=1100:h=44:color=${TBAR}:t=fill,\
drawbox=x=90:y=156:w=1100:h=1:color=${PBORDER}:t=fill,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTR}:fontsize=19:x=116:y=122,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTY}:fontsize=19:x=143:y=122,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTG}:fontsize=19:x=170:y=122,\
drawtext=fontfile=${NOTO}:text='${cap}':fontcolor=${CAPC}:fontsize=20:x=210:y=123" "$dir/bg.png" || return 1
  local vidlen aud target
  vidlen=$(python3 -c "import json;print(json.loads(open('$dir/demo.cast').read().splitlines()[-1])[0])")
  aud=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/narration.mp3")
  target=$(python3 -c "print(round(max($vidlen,$aud)+0.4,2))")
  ffmpeg -y -loop 1 -i "$dir/bg.png" -i "$dir/term.gif" -i "$dir/narration.mp3" -filter_complex "\
[1:v]scale=1076:404:force_original_aspect_ratio=decrease[g];\
[0:v][g]overlay=x=102:y=168:eof_action=repeat[v];[2:a]apad[a]" \
    -map "[v]" -map "[a]" -t "$target" -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac -movflags +faststart "$dir/demo.mp4"
}

# 実機デモ（非対話）。引数: dir cols rows caption footerver prog
# dir/cmds.sh（本物の claude を叩く）と dir/narration.mp3 を事前に用意しておく。
# 文字を大きく見せるため cols/rows は出力行数ぎりぎりに絞る（例: cols 92, rows 6〜11）。
build_demo() {
  local dir="$1" cols="$2" rows="$3" cap="$4" ver="$5" prog="$6"
  sed -i "s/^stty cols .*/stty cols ${cols} rows ${rows} 2>\/dev\/null || true/" "$dir/cmds.sh"
  ( cd "$dir" && asciinema rec demo.cast --overwrite -c "bash cmds.sh" ) || return 1
  render_demo "$dir" "$cap" "$ver" "$prog"
}

# 対話TUIコマンド（例 /powerup）を実演録画。tmux で PTY を与えて claude を起動し、
# バックグラウンドでキー送出しながら asciinema で録る。録画後は render_demo で描画。
# 引数: dir  "改行区切りの操作列（send-keys 引数）"    例:
#   record_tui demo/01-... $'/powerup\nEnter\nDown\nEnter\nEscape'
record_tui() {
  local dir="$1"; shift
  local keys="$1"
  local step="${STEP_WAIT:-2}" enddwell="${END_DWELL:-6}"
  local S="cctui$$"
  tmux kill-session -t "$S" 2>/dev/null
  local D; D=$(mktemp -d)
  tmux new-session -d -s "$S" -x 110 -y 30
  tmux send-keys -t "$S" "cd $D && TERM=xterm-256color claude" Enter
  timeout 9 tail -f /dev/null 2>/dev/null           # 起動待ち
  tmux send-keys -t "$S" Enter                       # 「このフォルダを信頼」を確定
  timeout 6 tail -f /dev/null 2>/dev/null
  tmux set -t "$S" status off 2>/dev/null
  ( timeout 2 tail -f /dev/null 2>/dev/null
    while IFS= read -r k; do
      [ -z "$k" ] && continue
      tmux send-keys -t "$S" "$k"
      timeout "$step" tail -f /dev/null 2>/dev/null
    done <<< "$keys"
    timeout "$enddwell" tail -f /dev/null 2>/dev/null   # 最終画面を保持（ここが held frame になる）
    tmux detach-client -s "$S"                           # kill でなく detach → 末尾に [exited] を出さない
  ) &
  asciinema rec "$dir/demo.cast" --overwrite -c "tmux attach -t $S"
  tmux kill-session -t "$S" 2>/dev/null                  # 録画終了後にセッション破棄
  rm -rf "$D"
  trim_tui_cast "$dir/demo.cast"                          # 末尾の [detached]/[exited] を削り、綺麗な最終フレームで終える
}

# 対話TUI cast の末尾チラ見え（tmux の [detached]/[exited] とその直前のクリア）を削除。
trim_tui_cast() {
  python3 - "$1" <<'PY'
import json,sys
p=sys.argv[1]; L=open(p).read().splitlines()
hdr=L[0]; evs=[json.loads(x) for x in L[1:] if x.strip()]
cut=None
for t,ch,data in evs:
    if ch=='o' and ('detached' in data or '[exited]' in data):
        cut=t-0.3; break
if cut is not None:
    evs=[e for e in evs if e[0]<cut]
open(p,'w').write(hdr+'\n'+''.join(json.dumps(e)+'\n' for e in evs))
PY
}

# 表紙（オープニング）。イベント名タイトル＋版レンジ。ヘッダー/フッター帯は使わないクリーンな1枚。
# 直下 cover.png（サムネ用の静止画）と dir/card.mp4（表紙＋ナレーション音声）を作る。
# 引数: dir verrange   例: build_cover demo/00-opening "2.1.90 → 2.1.114"
build_cover() {
  local dir="$1" ver="$2"
  local vf="\
drawtext=fontfile=${BOLD}:text='${COVER_L1}':fontcolor=${TITLEC}:fontsize=132:x=(w-tw)/2:y=96,\
drawtext=fontfile=${BOLD}:text='${COVER_L2}':fontcolor=${TITLEC}:fontsize=132:x=(w-tw)/2:y=250,\
drawtext=fontfile=${BOLD}:text='${COVER_L3}':fontcolor=${TITLEC}:fontsize=132:x=(w-tw)/2:y=404,\
drawbox=x=565:y=590:w=150:h=6:color=${TITLEC}:t=fill,\
drawtext=fontfile=${NOTO}:text='${ver}':fontcolor=${CREAM}:fontsize=44:x=(w-tw)/2:y=616"
  ffmpeg -y -f lavfi -i "$GRAD" -frames:v 1 -vf "$vf" cover.png || return 1     # サムネ用の静止画
  local dur; dur=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/narration.mp3")
  ffmpeg -y -f lavfi -i "$GRAD" -i "$dir/narration.mp3" -t "$dur" -vf "$vf" \
    -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac -shortest "$dir/card.mp4"
}

# ウィンドウ枠＋キャプション＋ヘッダー/フッターの背景（$dir/bg.png）だけ作る内部ヘルパ。
_win_bg() { # dir caption ver prog
  local dir="$1" cap="$2" ver="$3" prog="$4"
  ffmpeg -y -f lavfi -i "$GRAD" -frames:v 1 -vf "\
$(hf "$ver" "$prog"),\
drawbox=x=90:y=112:w=1100:h=468:color=${PANEL}:t=fill,\
drawbox=x=90:y=112:w=1100:h=468:color=${PBORDER}:t=2,\
drawbox=x=90:y=112:w=1100:h=44:color=${TBAR}:t=fill,\
drawbox=x=90:y=156:w=1100:h=1:color=${PBORDER}:t=fill,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTR}:fontsize=19:x=116:y=122,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTY}:fontsize=19:x=143:y=122,\
drawtext=fontfile=${NOTO}:text='●':fontcolor=${DOTG}:fontsize=19:x=170:y=122,\
drawtext=fontfile=${NOTO}:text='${cap}':fontcolor=${CAPC}:fontsize=20:x=210:y=123" "$dir/bg.png"
}

# 声と画面を同期させた対話TUIデモ。$dir/demo.cast（record_tui で録画済み）と
# $dir/beats.tsv（1行=1ビート、"秒<TAB>ナレーション"）から作る。
# 各ビートは「その秒の実画面（cast の静止フレーム）」を「そのナレーション音声の尺だけ」出す
# ＝画面の進行が声と一致する。TUI が長くて流し見にならない版はこれを使う。
build_synced() { # dir caption ver prog
  local dir="$1" cap="$2" ver="$3" prog="$4"
  agg --theme "$THEME" --font-family "Fira Code" --font-size 20 "$dir/demo.cast" "$dir/term.gif" || return 1
  _win_bg "$dir" "$cap" "$ver" "$prog" || return 1
  # beats.tsv が無ければ「最終フレーム＋ナレーション全文」で1ビート（単純なコマンドdemo向け）
  [ -f "$dir/beats.tsv" ] || printf 'end\t%s\n' "$(tr '\n' ' ' < "$dir/narration.txt")" > "$dir/beats.tsv"
  local i=0 t text; local list="$dir/.beats.txt"; : > "$list"
  # FD 3 で beats.tsv を読む＋ffmpeg に -nostdin（ループの stdin を食わせない。典型バグ回避）
  while IFS=$'\t' read -r t text <&3; do
    [ -z "${t// /}" ] && continue
    i=$((i+1))
    # 秒指定 or "end"（最終フレーム。agg の末尾パディングで tail の -ss は空振りするため -update で確実に取る）
    if [ "$t" = "end" ]; then
      ffmpeg -nostdin -y -i "$dir/term.gif" -update 1 "$dir/still$i.png" >/dev/null 2>&1 || return 1
    else
      ffmpeg -nostdin -y -ss "$t" -i "$dir/term.gif" -frames:v 1 "$dir/still$i.png" >/dev/null 2>&1 || return 1
    fi
    tts "$dir/b$i.mp3" "$text" || return 1
    # クリップ尺 = 音声尺で明示（-shortest はループ背景＋単一画像で効かず末尾に無音 padding が入るため）
    local bd; bd=$(ffprobe -v error -show_entries format=duration -of csv=p=0 "$dir/b$i.mp3")
    ffmpeg -nostdin -y -loop 1 -i "$dir/bg.png" -i "$dir/still$i.png" -i "$dir/b$i.mp3" -filter_complex "\
[1:v]scale=1076:404:force_original_aspect_ratio=decrease[g];[0:v][g]overlay=x=102:y=168[v]" \
      -map "[v]" -map 2:a -t "$bd" -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac "$dir/b$i.mp4" >/dev/null 2>&1 || return 1
    echo "file '$PWD/$dir/b$i.mp4'" >> "$list"
  done 3< "$dir/beats.tsv"
  ffmpeg -y -f concat -safe 0 -i "$list" -c copy "$dir/demo.mp4" >/dev/null 2>&1 \
    || ffmpeg -y -f concat -safe 0 -i "$list" -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac "$dir/demo.mp4" >/dev/null 2>&1
}

# 指定した mp4 群を順に連結。引数: 出力パス 入力mp4...（全て 1280x720 同一コーデック前提で -c copy）
_concat() {
  local out="$1"; shift
  : > /tmp/cc-concat.txt
  local f; for f in "$@"; do echo "file '$PWD/$f'" >> /tmp/cc-concat.txt; done
  ffmpeg -nostdin -y -f concat -safe 0 -i /tmp/cc-concat.txt -c copy "$out" \
    || ffmpeg -nostdin -y -f concat -safe 0 -i /tmp/cc-concat.txt -r 12 -c:v libx264 -pix_fmt yuv420p -c:a aac "$out"
}

# 再生順に demo.mp4 / card.mp4 を連結して session.mp4 に。引数なし。
concat_session() {
  local d fs=() f
  for d in $(ls -d demo/*/ | sort); do
    if [ -f "${d}demo.mp4" ]; then f="${d}demo.mp4"; elif [ -f "${d}card.mp4" ]; then f="${d}card.mp4"; else continue; fi
    fs+=("$f")
  done
  _concat session.mp4 "${fs[@]}"
}

# 抜粋プレビュー。引数: セグメントディレクトリ名...（demo/ 配下）。例:
#   build_preview 00-opening 01-2.1.90-powerup 02-2.1.91-deeplink-multiline 13-2.1.113-native-sandbox
build_preview() {
  local fs=() d f
  for d in "$@"; do
    if [ -f "demo/$d/demo.mp4" ]; then f="demo/$d/demo.mp4"; else f="demo/$d/card.mp4"; fi
    fs+=("$f")
  done
  _concat preview.mp4 "${fs[@]}"
}

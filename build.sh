#!/usr/bin/env bash
# Weekly Claude Code Live — セッション再生成ドライバ（この回のマニフェスト）。
# 保存済み素材（demo/*/demo.cast, narration.txt, beats.tsv, meta）から session.mp4 / preview.mp4 /
# cover.png を決定的に作り直す。`bash build.sh` で丸ごと再現。
#   前提: 事前に `.claude/skills/build-session/style.sh` のツール導入が済んでいること
#         （ffmpeg/asciinema/agg/edge-tts/Noto/Fira）。TUI録画(record_tui)は別途・保存済み cast を使う。
set -u
cd "$(dirname "$0")"
export PATH="$HOME/.local/bin:$PATH"
source .claude/skills/build-session/style.sh

# カード: dir bigfont bigtext bigsize subtitle footerver prog（narration.txt から音声を作る）
card() { local d="demo/$1"; shift
  tts "$d/narration.mp3" "$(tr '\n' ' ' < "$d/narration.txt")" || { echo "TTS FAIL $d"; return 1; }
  build_card "$d" "$@" || { echo "CARD FAIL $d"; return 1; }
}
# デモ: dir caption footerver prog（demo.cast＋beats.tsv、無ければ narration.txt で1ビート）
demo() { build_synced "demo/$1" "$2" "$3" "$4" || { echo "DEMO FAIL demo/$1"; return 1; }
  rm -f "demo/$1"/b[0-9].mp3 "demo/$1"/b[0-9].mp4 "demo/$1"/still[0-9].png "demo/$1"/.beats.txt; }

echo "▶ 表紙"
tts demo/00-opening/narration.mp3 "$(tr '\n' ' ' < demo/00-opening/narration.txt)"
build_cover demo/00-opening "2.1.90 → 2.1.114"

echo "▶ デモ（声と画面を同期 / build_synced）"
demo 01-2.1.90-powerup            "claude — 2.1.90  /powerup（対話レッスンを実演）"          "v2.1.90"  "02 / 16"
demo 02-2.1.91-deeplink-multiline "claude — 2.1.91  複数行ディープリンク"                    "v2.1.91"  "03 / 16"
demo 04-2.1.94-effort-default     "claude — 2.1.94  既定エフォート high"                     "v2.1.94"  "05 / 16"
demo 07-2.1.98-exclude-dynamic    "claude — 2.1.98  --exclude-dynamic-system-prompt-sections" "v2.1.98"  "08 / 16"
demo 12-2.1.111-opus47-xhigh      "claude — 2.1.111  Opus 4.7 xhigh"                          "v2.1.111" "13 / 16"
demo 13-2.1.113-native-sandbox    "claude — 2.1.113  ネイティブ化とサンドボックス"            "v2.1.113" "14 / 16"

echo "▶ カード"
card 03-2.1.92-cleanup            "$FIRA" "2.1.92"  104 "コマンド整理とセットアップ改善"            "v2.1.92"  "04 / 16"
card 05-2.1.96-bedrock-fix        "$FIRA" "2.1.96"  104 "Bedrock 認証の回帰修正"                    "v2.1.96"  "06 / 16"
card 06-2.1.97-focus-cjk          "$FIRA" "2.1.97"  104 "フォーカス表示と日本語補完"                "v2.1.97"  "07 / 16"
card 08-2.1.101-cert-onboarding   "$FIRA" "2.1.101" 104 "証明書ストア信頼とチーム・オンボーディング" "v2.1.101" "09 / 16"
card 09-2.1.105-precompact-webfetch "$FIRA" "2.1.105" 104 "PreCompact フックと WebFetch 改善"      "v2.1.105" "10 / 16"
card 10-2.1.108-skill-slash       "$FIRA" "2.1.108" 104 "モデルが組み込みスラッシュを起動"          "v2.1.108" "11 / 16"
card 11-2.1.110-tui-push          "$FIRA" "2.1.110" 104 "/tui とプッシュ通知ツール"                "v2.1.110" "12 / 16"
card 14-2.1.114-permdialog-fix    "$FIRA" "2.1.114" 104 "権限ダイアログのクラッシュ修正"            "v2.1.114" "15 / 16"
card 99-closing                   "$NOTO" "おつかれさまでした" 60 "次回は 2.1.116 から"            "→ 2.1.114" "16 / 16"

echo "▶ 連結"
concat_session
build_preview 00-opening 01-2.1.90-powerup 02-2.1.91-deeplink-multiline 13-2.1.113-native-sandbox

python3 -c "
import subprocess as s
for f in ('session.mp4','preview.mp4','cover.png'):
    d=s.run(['ffprobe','-v','error','-show_entries','format=duration','-of','csv=p=0',f],capture_output=True,text=True).stdout.strip()
    try: print(f'{f}: {int(float(d)//60)}:{int(float(d)%60):02d}')
    except ValueError: print(f'{f}: ok')
"

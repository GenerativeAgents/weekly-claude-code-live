---
name: build-session
description: Use when the user invokes `/build-session` to pre-generate the next Weekly Claude Code Live session as a ~45-minute "just watch" package — a narrated video that explains the Claude Code changelog since `.claude-code-version` and shows real terminal demos. Records real `claude` runs with asciinema, narrates them in Japanese with edge-tts (no API key), renders each segment to mp4 with agg/ffmpeg, and concatenates them into `session.mp4` (with `session.md`). Bootstraps ffmpeg/asciinema/agg/edge-tts if missing, updates `.claude-code-version` to the last covered version, and does not commit.
---

# build-session

Weekly Claude Code Live の**当日運用を省力化**するスキル。`.claude-code-version` の続きの
チェンジログを対象に、「解説＋実機デモ録画＋日本語TTSナレーション」を**事前に一式生成**し、
当日は **`session.mp4` を再生してただ眺めるだけ**にする。約45分に収め、修正ばかりの回では
重要な修正だけを扱う。

**このスキルは既存の `add-homework` スキルや `homework/*/demo/` の作法を踏襲しない**（独立設計）。
`verify.sh` や `cd demo/` 慣習、手順書きの型は使わない。成果物は**リポジトリ直下に1式**。

**想定入力:** `/build-session`（引数なし）

---

## 前提（ツール導入含む）

この環境には録画・TTS ツールが入っていないことがある。スキルの冒頭で**不足分を導入**する。
導入できない／ネットに出られない場合は**勝手に代替せず、人間に判断を仰いで中断**する。

必要なもの:

- **ffmpeg / ffprobe** — 動画合成と尺測定。
- **asciinema** — ターミナル実機録画（`.cast`）。
- **agg** — `.cast` を映像（GIF）化。`asciinema/agg` のリリース binary。
- **edge-tts** — 日本語ニューラル音声を **API キーなし** で生成（実行時ネット必須）。
- 既に `node` / `python3` / `curl` / 実 `claude` はある前提（無ければ人間に確認）。

導入レシピ（存在チェックしてから、足りないものだけ）:

```bash
mkdir -p "$HOME/.local/bin"; export PATH="$HOME/.local/bin:$PATH"

# ffmpeg / ffprobe
command -v ffmpeg  >/dev/null || sudo apt-get update -y && sudo apt-get install -y ffmpeg

# asciinema（apt → pip の順で試す）
command -v asciinema >/dev/null || sudo apt-get install -y asciinema \
  || python3 -m pip install --user asciinema

# agg（プラットフォームに合うリリース binary を取得。cargo 不要）
if ! command -v agg >/dev/null; then
  arch=$(uname -m)   # x86_64 なら x86_64-unknown-linux-gnu、arm64 なら aarch64-unknown-linux-gnu
  curl -fsSL -o "$HOME/.local/bin/agg" \
    "https://github.com/asciinema/agg/releases/latest/download/agg-${arch}-unknown-linux-gnu"
  chmod +x "$HOME/.local/bin/agg"
fi

# edge-tts（Debian は PEP 668 で pip 直挿しが塞がれるので pipx が確実）
if ! command -v edge-tts >/dev/null; then
  sudo apt-get install -y pipx && pipx install edge-tts \
    || { python3 -m ensurepip --user 2>/dev/null; python3 -m pip install --user edge-tts; } \
    || npm install -g msedge-tts   # node フォールバック
fi

# フォント（スタイル用）: 日本語 = Noto Sans CJK JP、コード/版番号 = Fira Code
fc-list | grep -qi notosanscjk || sudo apt-get install -y fonts-noto-cjk
fc-list | grep -qi firacode    || sudo apt-get install -y fonts-firacode
```

導入後に `ffmpeg -version`, `asciinema --version`, `agg --version`,
`edge-tts --list-voices | grep -i ja-JP`、`fc-list | grep -i notosanscjk` で疎通を確認する。
**どれか通らなければ人間に相談**。

> この環境での実績値: ffmpeg 5.1.9 / asciinema 2.2.0（`--cols/--rows` 非対応→cmds.sh の
> `stty` で幅固定）/ agg 1.9.0 / edge-tts 7.2.8（pipx）/ Noto Sans CJK JP + Fira Code。arch=aarch64。

**見た目は `style.sh` に集約**（同ディレクトリ）。`source .claude/skills/build-session/style.sh` して
`build_card` / `build_demo` / `concat_session` を使えば、下記のスタイルが全セグメントで揃う。

---

## 手順

1. **前提ツールを満たす** — 上記レシピで不足分を導入し疎通確認。無理なら人間に確認して中断。

2. **開始版を決める** — `.claude-code-version` を読み、その**次のパッチ版**を開始版にする
   （例: `2.1.89` → 開始 `2.1.90`）。

3. **CHANGELOG を取得** — 公式を取得してパースする:

   ```bash
   curl -fsSL https://raw.githubusercontent.com/anthropics/claude-code/main/CHANGELOG.md \
     -o /tmp/cc-changelog.md
   ```

   取得できなければ WebFetch で同 URL を読む。`## <x.y.z>` 見出し＝バージョン、配下の箇条書き
   ＝エントリ。**開始版〜最新を昇順**に並べる（＝古い方から）。

4. **作業ディレクトリを用意** — リポジトリ直下に出力する。既存の `session.md` / `session.mp4` /
   `demo/` があれば作り直す（毎回この1式を再生成）。

   ```bash
   rm -rf demo session.mp4 session.md && mkdir -p demo/00-opening demo/99-closing
   ```

5. **表紙（オープニング）を作る** — `demo/00-opening/narration.txt` からイントロ音声を作り、
   `build_cover demo/00-opening "<開始版> → <最終版>"` で**表紙**にする。イベント名
   「Weekly Claude Code Live」を大きなコーラルで出し、版レンジを残す（`build_cover` は同時に
   直下 `cover.png`＝サムネ用の静止画も出力）。これが総尺の起点。クロージングは `build_card`
   の日本語タイトルカードでよい。

6. **版を昇順に1つずつ処理**（`NN` は再生順の連番）。各版 `demo/NN-<version>-<slug>/` を、
   「fix の取捨基準」で **カード / デモ** に振り分けて作る。**デモは `build_synced` に一本化**
   （声とデモの進行が一致し、末尾の死んだ無音も出ない）:

   - **カード**（軽微版・言及） — `narration.txt` を書き、`build_card`（版番号）や `build_cover`
     （表紙）で静止カードに。
   - **コマンドデモ** — `cmds.sh` に本物の `claude` を叩く手順（非APIで完結するもの）を書いて
     `demo.cast` を録画 → `build_synced`。`beats.tsv` を**省略**すれば「最終フレーム＋ナレーション
     全文」で1ビート（`--help`/`--version` 系はこれで十分）。
   - **対話TUIデモ**（`/powerup` 等） — `record_tui` で起動〜操作を録画 → `beats.tsv`（`秒<TAB>…`
     か `end`）で**画面の切り替えをナレーションに同期** → `build_synced`（詳細は「2b」）。
   - **失敗時**: 実行が想定外に落ちた録画は採用せず、人間に「リトライ/スキップ/修正」を確認。
   - **45分判定**: `ffprobe` の実尺を走行合計に足し、**45:00 を超える手前で打ち切り**。

7. **クロージング** — `demo/99-closing/` に締めの音声つきカード（`build_card`）。

8. **連結** — `concat_session` で全採用セグメントを `session.mp4` に。必要なら `build_preview`
   で抜粋プレビュー `preview.mp4` も作る。

9. **`session.md` を書く**（直下）— 「テンプレート」の見出しに沿って、カバレッジ＆実尺テーブル、
   各セグメントの要点、素材リンク、再生方法を書く。

10. **版を更新** — `.claude-code-version` を**実際にカバーした最終版**へ書き換える。

11. **報告のみ** — 生成物パス（`session.mp4` / `preview.mp4` / `cover.png` / `session.md`）、
    カバー版範囲、総尺、**視聴コマンド**（後述）を短く返す。**`git add` / `commit` はしない**。

> **この回ぶんは `build.sh`（リポジトリ直下）にマニフェスト化する**。各セグメントの
> `build_card` / `build_synced` / `build_cover` 呼び出し（キャプション・版・進捗・字幕）を1本に
> まとめ、`bash build.sh` で**保存済み素材（cast・narration.txt・beats.tsv）から全部を決定的に
> 再生成**できるようにする（＝高い再現性）。録画（`record_tui`/`cmds.sh`）は初回のみ、以降は
> `build.sh` が cast を再利用する。

---

## 45分ルール

- 総尺は**推定でなく実測**で判定する。各 `demo.mp4` の `ffprobe` 実尺＋オープニング/クロージング
  の和が **45:00 を超えない手前で版を打ち切る**。
- 全版を回っても45分未満なら最新まで全部入れてよい（超えなければOK）。
- 端条件: 最初の1版だけで45分を超える場合は、**その版内でデモ本数を絞って**45分に収める。

尺の測り方:

```bash
ffprobe -v error -show_entries format=duration -of csv=p=0 demo/NN-.../demo.mp4
```

---

## fix の取捨基準（適応判断）

固定ルールにせず、**対象範囲の修正の量と重要度を実際に見て**決める。

- **個別デモする**のは重要なものだけ:
  - セキュリティ修正 / データ損失・正しさに関わる回帰 / 頻出UXの挙動変更 /
    チェンジログ自身が強調している項目。
- **量で出し分ける**:
  - 少数で意味のある修正 → ナレーションで1件ずつ短く触れる（専用デモなし）。
  - 多数で些末 → 「その他の修正 N件」を1ブロックにまとめて読み上げるだけ（簡易カード映像で可）。
  - 純内部リファクタ / 依存 bump のみ → 省略可。

---

## 録画・TTS・動画化のやり方（`style.sh` に集約）

**見た目の実体は `style.sh`**。各セグメントは **1280×720・暖色ダーク＋コーラルのアクセント**で統一し、
上下にヘッダー/フッター帯（`Weekly Claude Code Live`／版・進捗 `NN/16`）、デモは**ターミナル・ウィンドウ枠**
（信号ドット＋キャプション）に収める。全段が同一コーデックなので連結は `-c copy` で通る。

まず読み込む:

```bash
source .claude/skills/build-session/style.sh   # NOTO/FIRA/THEME と build_card/build_demo/concat_session
```

### 1) TTS ナレーション（先に用意。日本語・キー不要）

各 `demo/NN-.../narration.txt` から音声を作る（`build_card`/`build_demo` はこれを前提にする）:

```bash
edge-tts --voice ja-JP-NanamiNeural --file "$d/narration.txt" --write-media "$d/narration.mp3"
# 声は ja-JP-KeitaNeural 等に変更可。「2.1.91」等は「2てん1てん91」と読み下すと綺麗。
```

### 2) 実機デモ（本物を動かす）

`demo/NN-.../cmds.sh` に、本物の `claude` を叩く手順を書く（`step` で*打鍵風*に見せる）。
先頭の `stty` は `build_demo` が cols/rows を上書きするので気にしなくてよい:

```bash
# cmds.sh
stty cols 92 rows 8 2>/dev/null || true
PS='$ '
step() { printf '%s%s\n' "$PS" "$*"; sleep 1.0; eval "$*" 2>&1 || true; sleep 1.4; }  # 拒否デモ等で非0でも続行
step "claude --version"
step "claude <その版の新フラグ/挙動を示すコマンド>"
```

録画→テーマ付き映像化→音声合成までを一発で:

```bash
# build_demo  dir            cols rows caption                         footerver  prog
build_demo   demo/02-2.1.91-deeplink-multiline 92 11 "claude — 2.1.91  複数行ディープリンク" "v2.1.91" "03 / 16"
```

> **文字を大きく見せる要点**: agg は端末グリッド全体を描くので、`rows` を**実際の出力行数ぎりぎり**
> （＋2程度）に絞る。余白行が減り、幅制約で拡大される。cols は 92 前後が目安。
> **実行が想定外に落ちた録画は採用しない**。人間にリトライ/スキップ/修正を確認する。

### 2b) 対話TUIコマンドの実演（例 `/powerup`）＋**声と画面の同期**

`/powerup` のような**TUI内スラッシュコマンド**は、`--help` を見せるだけでなく**実際に起動して叩く**。

1. **録画** — `record_tui` が tmux で PTY を与えて `claude` を起動し（「このフォルダを信頼」を自動確定）、
   バックグラウンドでキーを送りながら asciinema で録る。**`kill` でなく `detach`＋末尾トリム**なので
   `[exited]`/`[detached]` は残らない（`trim_tui_cast` 自動適用）。**レッスンを開いた状態で終える**
   （`Escape` で戻さない）と、最後がきれいな画面になる。

   ```bash
   record_tui demo/01-2.1.90-powerup $'/powerup\nEnter\nDown\nDown\nEnter'   # 一覧→レッスンを開いて終わる
   ```

2. **ビート台本 `beats.tsv`** — 「秒<TAB>ナレーション」を1行=1ビートで書く。**その秒の実画面**を
   **そのナレーション音声の尺だけ**出す＝**声と画面の進行が一致**する（流し見・尺余りを防ぐ）。
   秒は `demo.cast` を agg 化した `term.gif` を見て、各状態が安定して映る時刻を選ぶ。

   ```
   9	…実行すると、この一覧が開きます。…      ← 一覧が映る秒
   18	…元に戻す、のレッスンを開きました。…    ← レッスンが映る秒
   18	…読んで、試して、完了マーク。ほかに…修正も。
   ```

3. **描画** — `build_synced` が各ビートの静止画＋音声を作って連結する:

   ```bash
   build_synced demo/01-2.1.90-powerup "claude — 2.1.90  /powerup（対話レッスンを実演）" "v2.1.90" "02 / 16"
   ```

> 認証は既存の `~/.claude/.credentials.json` を利用（API 課金が伴う操作は避け、`/powerup` の
> ように**ローカルで完結する対話**を選ぶ）。想定外に login 画面等が出たら人間に確認。
> TUI は全画面（〜30行）なので枠内では文字が小さめ。ナレーションで補う。
> **デモは `build_synced` に一本化**（コマンドデモも `beats.tsv` 省略で1ビート＝同期・無音なし）。
> `build_demo`（cast をそのまま流す旧方式）は残置するが、声とズレ・末尾静止が出るため通常は使わない。

### 3) カード（オープニング/クロージング/「その他の修正」/軽微版）

デモの無いセグメントは版番号（Fira Code）または日本語タイトル（Noto）の静止カード:

```bash
# build_card dir  bigfont bigtext        bigsize subtitle                 footerver  prog
build_card  demo/03-2.1.92-cleanup "$FIRA" "2.1.92" 104 "コマンド整理とセットアップ改善" "v2.1.92" "04 / 16"
build_card  demo/00-opening        "$NOTO" "最近のアップデートを眺める会" 60 "2.1.90 → 2.1.114" "start" "01 / 16"
```

> `<subtitle>` は短く（drawtext は自動改行しない）。`caption`/`subtitle` に `:` は使わない
> （drawtext のエスケープ回避）。

### 4) 連結・プレビュー・視聴

```bash
concat_session   # demo.mp4 / card.mp4 を再生順に -c copy 連結 → 直下 session.mp4
build_preview 00-opening 01-2.1.90-powerup 02-2.1.91-deeplink-multiline 13-2.1.113-native-sandbox  # 抜粋 → preview.mp4
```

**視聴**（コンテナには GUI が無いので）: ローカル限定の HTTP サーバを立て、VS Code のポート
転送でブラウザ再生する。**必ず `127.0.0.1` にバインド**（`0.0.0.0` は不可）:

```bash
python3 -m http.server 8000 --bind 127.0.0.1   # → ブラウザで http://localhost:8000/preview.mp4
```

（or VS Code エクスプローラーで `preview.mp4` を右クリック → Download して手元で再生。）

---

## 再現（build.sh）

この回ぶんの全セグメント呼び出しを **`build.sh`（リポジトリ直下）にマニフェスト化**する。
`bash build.sh` で、保存済み素材（`demo/*/demo.cast` ・ `narration.txt` ・ `beats.tsv`）から
`session.mp4` / `preview.mp4` / `cover.png` を**丸ごと決定的に再生成**できる。字幕・版・進捗などの
per-segment メタはここに集約する（引数で渡すだけだと再現できないため）。録画（`record_tui` /
`cmds.sh`）は初回のみで、以降は cast を再利用する。実物は `/workspaces/workspace/build.sh` を参照。

---

## 失敗時の扱い（human-in-the-loop）

- 実機実行が**想定外に失敗/エラー**した録画は**自動採用しない**。人間に
  「リトライ / スキップ / コマンド修正」を確認してから進む。
- TTS・agg・ffmpeg のエラーも同様に、勝手に代替せず人間に相談する。
- 「そのエラー自体が今日の見どころ」（例: 拒否・バリデーション）である場合は、
  それを**意図した挙動としてナレーションで説明**した上で採用する。

---

## 出力レイアウト（直下 1式）

```
build.sh                       # この回のマニフェスト兼ドライバ（bash build.sh で全再生成）
session.md                     # マスター台本: カバレッジ＆実尺表＋要点＋再生方法
session.mp4                    # 本編（1280×720・約45分・音声つき）＝眺める会本体
preview.mp4                    # 抜粋プレビュー（build_preview）
cover.png                      # 表紙の静止画（build_cover が生成。connpass サムネ等に使える）
demo/
  00-opening/                  # 表紙（narration.txt / meta.txt → cover.png / card.mp4）
  NN-<version>-<slug>/         # 採用デモ項目（NN=再生順）※★= build.sh の再生成に必要な素材
    cmds.sh                    # コマンドデモの実行列（record_tui 版には無い）
    demo.cast    ★            # asciinema 実機録画（保存＝再録画不要）
    beats.tsv    ★            # 声と画面の同期台本（秒/end<TAB>ナレーション。省略で1ビート）
    narration.txt ★           # カード/フォールバック用の読み上げ原稿
    term.gif / bg.png          # agg 映像化 / ウィンドウ背景（build_synced が都度生成）
    narration.mp3 / demo.mp4   # 生成物（音声 / 1280×720 単体動画。カード回は card.mp4）
  99-closing/                  # 締めカード
```
（スタイル定義は `.claude/skills/build-session/style.sh`。カード回は `demo.mp4` の代わりに `card.mp4`。）

---

## テンプレート（session.md の見出し）

```markdown
# Weekly Claude Code Live — <開始版> 〜 <最終版>（約 <MM:SS>）

当日はこの `session.md` を開きつつ [`session.mp4`](./session.mp4) を再生して眺めるだけ。
個別素材は各 `demo/NN-.../` を参照。

## 収録内容と尺

| # | 版 | 見どころ | 種別 | 尺 |
| --- | --- | --- | --- | --- |
| 00 | — | オープニング | カード | 0:xx |
| 01 | 2.1.90 | <機能名> | デモ | m:ss |
| .. | .. | その他の修正 N件 | 言及 | m:ss |
| 99 | — | クロージング | カード | 0:xx |
|    |    | **合計** |    | **MM:SS（≤45:00）** |

## セグメント

### 01 — 2.1.90 <機能名>  [demo/01-2.1.90-<slug>/](./demo/01-2.1.90-<slug>/)

<この版が何を変えたかの解説（ナレーション本文そのまま）>

- 録画: [demo.mp4](./demo/01-2.1.90-<slug>/demo.mp4) / 元 cast: demo.cast
- 実行コマンド: cmds.sh

（以降セグメントごとに繰り返し）

## 今回カバーしなかった版

<45分に収まらず次回送りにした版があれば列挙。無ければ「最新まで到達」>

## 再生方法

- 本編を通しで: `session.mp4` を再生（プレイヤー or `ffplay session.mp4`）。
- 個別に見たい: `demo/NN-.../demo.mp4`。
```

---

## 撤回

- 「さっきの session は取り消して」と言われたら、直下の `session.md` / `session.mp4` /
  `demo/` を削除し、`.claude-code-version` を実行前の値へ戻す。
- 導入したツール（ffmpeg 等）はシステム側なので既定では残す。消したい場合のみ人間の指示に従う。

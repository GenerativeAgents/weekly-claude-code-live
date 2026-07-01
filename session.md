# Weekly Claude Code Live — 2.1.90 〜 2.1.114（約 12:47）

> プレビュー: [`preview.mp4`](./preview.mp4)（表紙＋2.1.90・2.1.91・2.1.113 の3本、約 3:03）。
> この3本は「声と画面を同期」させた版（`build_synced`）。他の版は順次同方式へ移行予定。

当日はこの `session.md` を開きつつ [`session.mp4`](./session.mp4) を再生して眺めるだけ。
個別素材は各 `demo/NN-.../` を参照。実機デモは本物の `claude`（v2.1.197）を動かして録画。
映像は 1280×720、ヘッダー/フッター帯＋ターミナル・ウィンドウ枠のスタイル付き（コーラル系アクセント、
Noto Sans JP / Fira Code、ターミナルは agg のカスタム暖色テーマ）。

## 収録内容と尺

| # | 版 | 見どころ | 種別 | 尺 |
| --- | --- | --- | --- | --- |
| 00 | — | オープニング | カード | 0:35 |
| 01 | 2.1.90 | `/powerup` を実演（レッスン一覧→「元に戻す」・声と画面を同期） | デモ | 0:58 |
| 02 | 2.1.91 | `claude-cli://` 複数行ディープリンク（声と画面を同期） | デモ | 0:52 |
| 03 | 2.1.92 | `/tag`・`/vim` 廃止／Bedrockウィザード | カード | 0:54 |
| 04 | 2.1.94 | 既定エフォートを high へ | デモ | 0:52 |
| 05 | 2.1.96 | Bedrock 認証の回帰修正 | カード | 0:26 |
| 06 | 2.1.97 | フォーカス表示・日本語補完 | カード | 0:51 |
| 07 | 2.1.98 | `--exclude-dynamic-system-prompt-sections`・Bash権限修正 | デモ | 1:07 |
| 08 | 2.1.101 | OS証明書ストア信頼・`/team-onboarding` | カード | 0:58 |
| 09 | 2.1.105 | PreCompactフック・WebFetch改善 | カード | 0:59 |
| 10 | 2.1.108 | モデルが組み込みスラッシュを起動・`/recap` | カード | 0:52 |
| 11 | 2.1.110 | `/tui`・プッシュ通知ツール | カード | 0:52 |
| 12 | 2.1.111 | Opus 4.7 `xhigh`・`/ultrareview` | デモ | 1:06 |
| 13 | 2.1.113 | ネイティブバイナリ化・`sandbox.network.deniedDomains`（声と画面を同期） | デモ | 0:38 |
| 14 | 2.1.114 | 権限ダイアログのクラッシュ修正 | カード | 0:21 |
| 99 | — | クロージング | カード | 0:31 |
|    |    | **合計** |    | **12:47（≤45:00）** |

## セグメント

各セグメントのナレーション全文は `demo/NN-.../narration.txt`、実機で流したコマンドは
`demo/NN-.../cmds.sh`、単体動画は `demo/NN-.../demo.mp4`（カード回は `card.mp4`）。

- **01 — 2.1.90** [demo/01-2.1.90-powerup/](./demo/01-2.1.90-powerup/) — `/powerup`（対話式レッスン）が目玉。実機で claude を起動し **`/powerup` を実演**：「Power-ups 0/10」のレッスン一覧→「元に戻す（`/rewind`・Esc Esc）」レッスンを開いて中身を表示。レート制限ダイアログの無限ループ、`--resume` のプロンプトキャッシュ取りこぼし回帰も修正。録画は tmux+asciinema（`style.sh` の `record_tui`）。
- **02 — 2.1.91** [demo/02-2.1.91-deeplink-multiline/](./demo/02-2.1.91-deeplink-multiline/) — `claude-cli://open?q=` が複数行（`%0A`）を受理。実機で `claude --handle-uri` に3行を渡してパース通過を実演、余計な引数の拒否ガードも提示。`disableSkillShellExecution` 設定、プラグイン `bin/` 実行も。
- **03 — 2.1.92** [demo/03-2.1.92-cleanup/](./demo/03-2.1.92-cleanup/) — `/tag`・`/vim` 廃止、対話式 Bedrock セットアップ、`/cost` 内訳、`/release-notes` ピッカー化。
- **04 — 2.1.94** [demo/04-2.1.94-effort-default/](./demo/04-2.1.94-effort-default/) — 既定エフォートが medium→high。実機ヘルプで `--effort <level>` を確認。Mantle 経由 Bedrock、Slack 送信ヘッダも。
- **05 — 2.1.96** [demo/05-2.1.96-bedrock-fix/](./demo/05-2.1.96-bedrock-fix/) — 2.1.94 で入った Bedrock 認証ヘッダ欠落（403）の回帰修正のみ。
- **06 — 2.1.97** [demo/06-2.1.97-focus-cjk/](./demo/06-2.1.97-focus-cjk/) — フォーカスビューが no-flicker でも動作。日本語/中国語の `/`・`@` 補完が句読点後でも発火。`refreshInterval` ステータスライン、Cedar ハイライト。
- **07 — 2.1.98** [demo/07-2.1.98-exclude-dynamic/](./demo/07-2.1.98-exclude-dynamic/) — `--exclude-dynamic-system-prompt-sections`（実機ヘルプで確認）、Perforce モード、Monitor ツール。Bash 権限バイパスを多数修正。
- **08 — 2.1.101** [demo/08-2.1.101-cert-onboarding/](./demo/08-2.1.101-cert-onboarding/) — OS の CA ストアを既定信頼（`CLAUDE_CODE_CERT_STORE`）。`/team-onboarding`。`which` フォールバックのコマンドインジェクション、メモリリークを修正。
- **09 — 2.1.105** [demo/09-2.1.105-precompact-webfetch/](./demo/09-2.1.105-precompact-webfetch/) — PreCompact フック（圧縮をブロック可能）、`monitors` マニフェスト、WebFetch が style/script を除去、`/proactive`=`/loop`。
- **10 — 2.1.108** [demo/10-2.1.108-skill-slash/](./demo/10-2.1.108-skill-slash/) — モデルが Skill 経由で `/init`・`/review` 等の組み込みスラッシュを起動可能に。`/recap`、1時間キャッシュ TTL、`/undo`=`/rewind`。
- **11 — 2.1.110** [demo/11-2.1.110-tui-push/](./demo/11-2.1.110-tui-push/) — `/tui`（ちらつきのない描画）、プッシュ通知ツール、`Ctrl+O` の役割整理と `/focus`。
- **12 — 2.1.111** [demo/12-2.1.111-opus47-xhigh/](./demo/12-2.1.111-opus47-xhigh/) — Opus 4.7 `xhigh` エフォート（実機ヘルプで確認）、`/ultrareview`（クラウド並列レビュー）、`/effort` スライダー、auto モード解禁。
- **13 — 2.1.113** [demo/13-2.1.113-native-sandbox/](./demo/13-2.1.113-native-sandbox/) — CLI がネイティブ Claude Code バイナリを起動（実機 `--version`）。`sandbox.network.deniedDomains`。Bash 拒否ルールが `env`/`sudo`/`watch` ラッパにも一致、`find -exec`/`-delete` を自動承認しない。
- **14 — 2.1.114** [demo/14-2.1.114-permdialog-fix/](./demo/14-2.1.114-permdialog-fix/) — エージェントチームのツール権限要求時の権限ダイアログ・クラッシュ修正のみ。

## 今回カバーしなかった版

2.1.116 以降は次回。範囲は「45分を超えない」制約に収まっており、今回は 2.1.90〜2.1.114 を約14分で通した。
より 45 分に近づけたい場合は、続きの版を追加生成できる。

## 再生方法

- 本編を通しで: `session.mp4` を再生（プレイヤー、`ffplay session.mp4`、または `mpv session.mp4`）。
- 個別に見たい: `demo/NN-.../demo.mp4`（カード回は `card.mp4`）。
- 元のターミナル録画: `demo/NN-.../demo.cast`（`asciinema play <file>` で再生可能）。

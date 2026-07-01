# プロトコルハンドラーの登録をdisableDeepLinkRegistration防止する設定を追加しました。claude-cli://

（原文: "Added the `disableDeepLinkRegistration` setting to prevent registration of the
`claude-cli://` protocol handler."）

対象バージョン: ディープリンク機能自体は Claude Code **v2.1.91+**（公式ドキュメント明記）。
`disableDeepLinkRegistration` 設定はこの回（v2.1.89 追従時点）のチェンジログ行。
本メモの実装確認はローカルにインストール済みの **v2.1.197 バイナリ**で行った。

## 疑問

changelog 1 行だと、何を「登録」して何を「防止」するのか分からなかった。

- `claude-cli://` とは何か。誰がいつ OS に登録するのか
- ディープリンクをクリックすると具体的に何が起きるのか（コードが勝手に走る？）
- `disableDeepLinkRegistration` は boolean？ 値は何を入れる？
- 「登録を防止」すると、既に登録済みのハンドラも消える？ ディープリンク機能ごと無効になる？
- そもそも何が嬉しくて、なぜわざわざ止めたい設定を足したのか（セキュリティ？管理環境？）

## まとめ（先に結論）

- **`claude-cli://` は Claude Code が OS に登録するカスタム URL スキーム**（`mailto:` と同類）。
  対話セッションを**初めて起動したとき**に、macOS/Linux/Windows へ**ユーザー領域だけ**に登録される。
  インストールとは別の、起動時の自動ハンドシェイク。
- **クリックすると新しいターミナルが開き、指定リポジトリで Claude Code が起動、プロンプト欄に
  文面が入力済みで待つ**。URL 形式は `claude-cli://open?cwd=…&repo=…&q=…` の 1 アクション
  （`open`）のみ。ランブック・アラート・ダッシュボードに「ワンクリックの起点」を仕込める。
- **`disableDeepLinkRegistration` は文字列 enum で、取れる値は `"disable"` の一択**
  （バイナリの実体: `v.enum(["disable"]).optional()`）。`settings.json` に
  `"disableDeepLinkRegistration": "disable"` と書くと、**起動時の OS 登録処理を丸ごと
  スキップ**する。boolean ではない。
- **これは「登録」を止める設定であって「機能」を消す設定ではない**。既に登録済みの
  ハンドラ実体（.app / .desktop / レジストリ）はこの設定では**消えない**し、既存ハンドラに
  URL がディスパッチされれば `--handle-uri` は依然動く。完全に断つには**既存の登録実体も
  手で削除**する必要がある。
- **狙いは管理・制限された環境**。プロトコルハンドラ登録が禁止/別管理の PC、共有 VM、
  ロックダウンされた企業端末など。組織で強制したいなら **managed settings** に置いて
  ユーザーが上書きできないようにする。

出典:
[deep-links.md](https://code.claude.com/docs/en/deep-links) /
[settings.md](https://code.claude.com/docs/en/settings) /
ローカル v2.1.197 バイナリの逆アセンブル（登録関数・URL パーサ・引数ガード）

## `claude-cli://` ディープリンクとは

> A deep link is a `claude-cli://` URL that opens Claude Code in a new terminal window.
> The URL can carry a working directory and a prompt to pre-fill. — deep-links.md

URL は `mailto:` と同じ「カスタムスキーム」。ブラウザや Slack でリンクをクリックすると、
OS が `claude-cli://` を認識して**手元の Claude Code を起動**する。リンク自体はどこにでも
置ける（Web ページ / wiki / アラート / CI 通知）が、**セッションは常にクリックした
ローカルマシンで開く**。

### URL 形式（`open` アクションのみ）

パーサ（バイナリの `oCc`）は `hostname` が `open` 以外を**全部拒否**する。
`claude-cli://open` に続けてクエリパラメータを付ける:

| パラメータ | 中身 | 検証（バイナリ実測） |
| --- | --- | --- |
| `q` | プロンプト欄に**入力される**文面（URL エンコード必須、`%0A` で改行） | 最大 **5000 文字**。超過で拒否 |
| `cwd` | 作業ディレクトリ（絶対パス） | UNC/ネットワークパス拒否、不可視/双方向制御文字を含むと拒否 |
| `repo` | GitHub の `owner/name` スラッグ。最後に使ったローカルクローンに解決 | 正規表現 `/^[\w.-]+\/[\w.-]+$/`。不一致で拒否。クローン未発見なら**ホームで開く** |

`cwd` と `repo` を両方渡すと **`cwd` が優先**（`repo` は無視）。

例（ランブックに貼る想定）:

```text
claude-cli://open?repo=acme/payments&q=Investigate%20the%20failed%20deploy.%0ACheck%20recent%20commits.
```

### クリックしたら何が起きるか（受信フロー）

1. ブラウザ/アプリが URL を OS に渡す
2. OS が `claude-cli://` を認識し、登録済みハンドラ（= `claude --handle-uri <uri>`）を起動
3. **新しいターミナルウィンドウ**が開き、指定ディレクトリで Claude Code が走り、
   プロンプト欄に `q` の文面が**入力済み**で表示される
4. ユーザーが読んで、必要なら編集し、**Enter を押して初めて送信**される

> A deep link never executes anything on its own. … nothing reaches the model until you
> read what was filled in and press Enter. — deep-links.md

入力欄の下に `Prompt from an external link` の警告が出て、送信/クリアするまで残る。
1000 文字超のプロンプトは文字数付きで「スクロールして全文を確認してから Enter」と促す
（長文で指示を画面外に押し出す攻撃対策）。

## OS への登録 —「登録」の実体

Claude Code は **macOS/Linux/Windows で初回の対話セッション起動時**にハンドラを登録する。
別途インストールコマンドは不要。**書き込むのはユーザー領域だけ**（root 不要）。

| OS | 登録先 | 実体 |
| --- | --- | --- |
| macOS | `~/Applications/Claude Code URL Handler.app` | Info.plist に `CFBundleURLSchemes=[claude-cli]`、`lsregister -R` で登録 |
| Linux | `$XDG_DATA_HOME/applications/claude-code-url-handler.desktop`（既定 `~/.local/share/applications`） | `.desktop` + `xdg-mime default … x-scheme-handler/claude-cli` |
| Windows | `HKEY_CURRENT_USER\Software\Classes\claude-cli` | `URL Protocol` + `shell\open\command = "…\claude" --handle-uri "%1"` |

登録は**冪等**（既に自分の Exec 行があれば何もしない）、**非ブロッキングのベストエフォート**
で、失敗すると warn して `.deep-link-register-failed` マーカーで **24h バックオフ**、
通常は **1 時間ごとに再チェック**する。**対話起動のときだけ**走る（`-p` や
`--handle-uri` 実行では走らない）。

### 実物（このデモ環境に既にあった）

このボックスでは過去の対話起動時に Claude Code が実際に書いた `.desktop` が残っていた:

```ini
# ~/.local/share/applications/claude-code-url-handler.desktop
[Desktop Entry]
Name=Claude Code URL Handler
Comment=Handle claude-cli:// deep links for Claude Code
Exec="/home/vscode/.local/bin/claude" --handle-uri %u
Type=Application
NoDisplay=true
MimeType=x-scheme-handler/claude-cli;
```

ただし**このコンテナには `xdg-mime` も端末エミュレータも無い**ので、
`.desktop` の書き込みは成功しても mime 関連付け（`xdg-mime default …`）は完了しておらず、
`xdg-mime query default x-scheme-handler/claude-cli` は何も返さない。「登録はベストエフォート」
「headless では半分しか効かない」を地で行く状態で、デモの導入に使える。

## `disableDeepLinkRegistration` 設定 — 今日の主役

`settings.json` の**トップレベルキー**。値は `"disable"` の一択:

```json
{ "disableDeepLinkRegistration": "disable" }
```

バイナリの設定スキーマ:

```js
disableDeepLinkRegistration: v.enum(["disable"]).optional()
  .describe("Prevent claude-cli:// protocol handler registration with the OS")
```

効くのは登録関数の冒頭 1 行:

```js
async function dCc(){
  if (Or().disableDeepLinkRegistration === "disable") return;  // ← ここで即 return
  // …platform チェック → 冪等チェック → pEf() で実際に OS 登録…
}
```

つまり `"disable"` があると**起動時の OS 登録（`.desktop` 書き込み / plist / レジストリ）を
一切やらない**。

### 「登録の防止」の正確な意味（ここ重要）

- **止めるのは登録だけ**。既に登録済みのハンドラ実体はこの設定では**消えない**。
  1 時間ごとの再チェックもスキップされるので、既存 `.desktop` はそのまま残る。
- したがって**この設定 = ディープリンク機能の全面 OFF ではない**。既存ハンドラに URL が
  ディスパッチされれば `claude --handle-uri` は依然として動く。
- **完全に断ちたい**なら、`"disable"` を入れた**上で**、既存の登録実体
  （macOS の `.app` / Linux の `.desktop` + `xdg-mime` / Windows のレジストリキー）も
  手で削除する。
- 組織で強制するなら **managed settings**（`/en/server-managed-settings`）に置き、
  ユーザーが `settings.json` で上書きできないようにする。

### なぜこんな設定が要るのか

- プロトコルハンドラ登録が**禁止/別管理**の環境（IT 管理下の企業端末、共有 VM、
  golden image）で、起動のたびに `~/.local/share/applications` などへ書き込むのを止めたい
- ハンドラ登録という**副作用そのものを嫌う**ユーザー（最小権限・再現可能環境志向）
- deep link を使う予定が無いので、登録処理・再チェックを丸ごと省きたい

## セキュリティ設計（`--handle-uri` は攻撃面なので固い）

deep link は「外部（Web/チャット）から手元の CLI を叩く」経路なので、受信側は多層で守られている。
以下はすべて**実 v2.1.197 バイナリを headless で叩いて確認**した挙動:

1. **プロンプトは inert**: `q` は**入力されるだけで送信されない**。モデルに何も届かない。
   `Prompt from an external link` 警告が出続ける。
2. **引数インジェクション防御**: OS ハンドラは厳密に `--handle-uri <uri>` だけを渡す。
   URI の後ろに余分な引数があると**即拒否**（`claude --handle-uri "…" EXTRA` → exit 1）:
   > claude: rejected deep-link invocation — unexpected arguments after the URI.
   > …extra arguments indicate argument injection via the URL.
3. **アクションは `open` のみ**: `claude-cli://danger?q=x` →
   `Deep link error: Unknown deep link action: "danger"`
4. **`cwd` サニタイズ**: UNC/ネットワークパス拒否
   （`… UNC / network paths are not supported`）、不可視/双方向制御文字拒否
   （`… contains invisible or bidirectional control characters`）
5. **`repo` は `owner/name` 形式必須**、**`q` は 5000 文字上限**
   （`Deep link query exceeds 5000 characters`）
6. **スキーム固定**: `https://…` を渡しても
   `expected claude-cli:// scheme` で拒否
7. 権限ルール・`CLAUDE.md`・ディレクトリの信頼プロンプトは通常セッションと同じに適用される。

## 前提・制約

- ディープリンク機能は **Claude Code v2.1.91+**
- 登録は**対話起動時のみ**、ユーザー領域のみ。root 不要
- リンクを表示する側が**カスタムスキームを許可**している必要がある。**GitHub の Markdown は
  `claude-cli://` を剥がす**（README/issue/PR/wiki ではラベルだけ表示・リンク無効）。
  回避策はコードブロックに URL を貼って手でアドレスバーに入れてもらう
- 端末エミュレータの検出: macOS は直近の対話端末を記憶（iTerm2/Ghostty/kitty/Alacritty/
  WezTerm/Terminal.app）、Linux は `$TERMINAL` → `x-terminal-emulator` → 一般的な候補、
  Windows は Windows Terminal → PowerShell → `cmd.exe`
- headless（DE 無し）だと `xdg-open` の飛ばし先が無い＝クリックが何も起きない

## 他機能との使い分け

- **`claude-cli://` deep link**: リンク → **新しいローカル端末**で Claude 起動＋プロンプト前入力
- **VS Code 拡張のハンドラ** `vscode://anthropic.claude-code/open`: 端末ではなく
  **エディタタブ**で Claude Code を開く（別スキーム・別ハンドラ）
- **非対話モード（headless）** `-p`: 端末を開かずスクリプトから実行して出力を取る

## 有効な活用シーン

勝ち筋は **「プロンプトを書く人」と「踏む人」が別**で、**リンクがターミナルの外**
（アラート/wiki/チャット/課題管理）に置かれるとき。自分用の一回きりは素直に `claude` と
打つ方が速い。

チーム運用系（本命）:

- **インシデント・ランブック**（PagerDuty/Notion/社内wiki）: オンコールが誰でも、対象
  リポジトリ＋吟味済みの初動プロンプトで始まる。属人性が消える
- **監視アラート/ダッシュボード**（Grafana/Datadog）: 発火した指標・サービスに絞った
  調査プロンプトへ直行
- **CI 失敗通知**（Slack/GitHub Actions 本文）: 失敗ジョブ名を前入力して開く
- **Issue/バグ再現**（Linear/Jira の「ローカルで調べる」リンク）: 1クリックで該当
  リポジトリに入って再現・調査

個人・開発フロー系:

- **オンボーディング**（README/社内ポータル）: 新人が開いた瞬間に案内プロンプトが待つ
- **Web/モバイル → ローカルへ引き継ぎ**: claude.ai やスマホで見つけた件を、手元の実環境
  （自分の認証・ファイル）で続行
- **デモ・登壇・ブログ**: 「この例を自分の環境で試す」リンクでコピペ/`cd` 不要

効かせるコツ:

- **長い定型は Skill 化して `q=/skill-name` で呼ぶだけ**にする（5000字制限も回避。deep link
  は「外からの入口」、Skill は「中の再利用本体」で組み合わせる）
- 置き場所は **GitHub 以外**（GitHub Markdown は `claude-cli://` を剥がす）
- `repo=owner/name` は「最後に使ったクローン」に解決＝チーム配布向き。全員パスが同じ
  （devcontainer/golden VM）なら `cwd=` が確実

一言で: **機械（アラート/CI）や別ツール（wiki/チャット/課題管理）が起点になって、正しい
リポジトリの吟味済みプロンプトへ人を運ぶ橋**。

例（そのままアドレスバー/シェルに貼れる）:

```text
claude-cli://open?repo=acme/web-gateway&q=web-gateway%20の%205xx%20が急増。直近30分のエラーログと最近のデプロイを調べて。
```

## デモ

> **次回「デモして」と言われたら、まず上の「有効な活用シーン」を回答してから実演に入る。**

`claude-cli://` の**受信側は実バイナリで headless でも動く**（`claude --handle-uri`）ので、
実物の `claude` にディープリンクをパース・検証・拒否させて見せられる。**登録側**は
このマシンにある実物 `.desktop` と、公式ロジックを Node に移植した
`deep-link-register.mjs` で `"disable"` の効き目（登録される/されない）を再現する。
当日手順と PASS を見せるハーネスは [demo/](./demo/) 配下。実行は必ず `demo/` に `cd` してから。

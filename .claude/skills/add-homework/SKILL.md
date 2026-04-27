---
name: add-homework
description: Use when the user invokes `/add-homework <slug> <changelog line>` during a Weekly Claude Code Live session to record a Claude Code changelog entry they did not fully understand and want to carry over as homework for next session's demo. Creates homework/YYYYMMDD/<slug>/homework.md (with an empty demo/ subdirectory) and adds a README link on the first homework of the session. Does not commit.
---

# add-homework

Weekly Claude Code Live のセッション中、チェンジログを追いかけていて「この 1 行はよく
分からなかった」と思ったときに呼び出されるスキル。

**想定入力:** `/add-homework <slug> <changelog line>`

- 第 1 引数 `<slug>`: そのトピックを表す短い slug（英小文字 + ハイフンのみ、例: `agent`,
  `hooks-matcher`, `mcp-http`）。ディレクトリ名になる。
- 残り全部 `<changelog line>`: チェンジログ 1 行の原文。整形・要約・翻訳しない。

## 前提

- 1 セッション = 1 日付ディレクトリ。`homework/YYYYMMDD/`（ハイフンなし 8 桁、実行時点の日付）。
- 宿題 1 件 = 1 サブディレクトリ。`homework/YYYYMMDD/<slug>/` の中身は次の通り:
  - `homework.md` — 疑問・調査メモ・使い分け等の writeup。
  - `demo/` — 次回冒頭デモで使う実物を置くディレクトリ（スキル作成時点では空ディレクトリ
    を確保するため `.gitkeep` を置く）。
- README の `### [homework/](./homework)` セクションには、その日のディレクトリへのリンクを
  1 行だけ持つ。
- ファイル編集のみ。`git add` / `git commit` はしない。

## 手順

1. **引数を取り出す**
   - 最初の空白までを `<slug>` として取り出す。
   - 残り全部を trim して `<changelog line>` として扱う。前後の空白・改行は落とす。
     それ以外は改変しない（バッククォート、記号、英語/日本語混在もそのまま保持）。
   - `<slug>` が空、または `^[a-z][a-z0-9-]*$` にマッチしないときは、使える slug を 1 度だけ
     確認する（例: `agent`, `hooks-matcher`）。
   - `<changelog line>` が空なら、何を宿題にしたいか 1 度だけ確認する。

2. **対象日を決める**
   - システムの currentDate を `YYYYMMDD` 形式（ハイフンなし 8 桁）に整形する。
   - 対象ディレクトリ: `homework/YYYYMMDD/<slug>/`

3. **衝突チェック**
   - `homework/YYYYMMDD/<slug>/` が既に存在するなら、新規作成はせず「既出（`<slug>`）」と
     報告する。内容の上書き・追記はしない。ユーザーから別 slug を提示されるまで待つ。

4. **宿題ファイルを作成する**
   - ディレクトリ `homework/YYYYMMDD/<slug>/` を作る。
   - `homework/YYYYMMDD/<slug>/homework.md` を以下のテンプレートで新規作成:

     ```markdown
     # <changelog line>

     ## 調査メモ

     （未着手）

     ## デモ

     当日のライブ手順と必要な実物は [demo/](./demo/) 配下。
     ```

     先頭 `#` 見出しに引数原文をそのまま入れる。補足・翻訳・注釈は付けない。

5. **demo/ ディレクトリを用意する**
   - `homework/YYYYMMDD/<slug>/demo/` を作る。
   - 中身を残すため `homework/YYYYMMDD/<slug>/demo/.gitkeep` を空ファイルで置く。

6. **README にリンクを足す（その日の初回のみ）**
   - `README.md` の `### [homework/](./homework)` セクション配下の箇条書きに、今日の
     `homework/YYYYMMDD/<slug>/` へのリンクがあるか確認。
   - まだ同日分のリンクが 1 件もなければ末尾に 1 行追記する:

     ```
     - [homework/YYYYMMDD/<slug>/](./homework/YYYYMMDD/<slug>)
     ```

   - 同日分のリンクが既にあり、今回の slug とは違う場合も、その行に追記する。具体的には:
     - 既存行: `- [homework/YYYYMMDD/<existing-slug>/](./homework/YYYYMMDD/<existing-slug>)`
     - これを同日分 2 件目以降の slug を足して、次の形に書き換える:

       ```
       - homework/YYYYMMDD/ — [<existing-slug>](./homework/YYYYMMDD/<existing-slug>) / [<new-slug>](./homework/YYYYMMDD/<new-slug>)
       ```
     - 以後の 3 件目以降も末尾に ` / [<slug>](...)` を足していく。

7. **報告のみで終える**
   - 作成した `homework.md` のパスと、引数として記録した 1 行を短く返す。`git` 操作はしない。

## 撤回

- 「さっきの宿題は取り消して」と言われたら、直前に作成した `homework/YYYYMMDD/<slug>/`
  ディレクトリを丸ごと削除する。
- 削除後にその日のディレクトリが空になるなら、`homework/YYYYMMDD/` 自体と README の
  リンク行も削除する。
- 同日分のリンクが複数 slug を含んでいる行だった場合は、該当 slug 部分だけを落として
  行を書き直す。

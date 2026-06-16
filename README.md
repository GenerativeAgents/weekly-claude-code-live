# Weekly Claude Code Live

毎週ランチタイムに 1 時間程度で開催するウェビナーのリポジトリ。
書籍『実践Claude Code入門』以降の Claude Code のアップデートを毎週追いかけ、
追いついたところまでを記録として残していく。

## このリポジトリの使い方

### [.claude-code-version](./.claude-code-version)

直近の回で「ここまで追いついた」Claude Code のバージョンを 1 行で記録する。

### [homework/](./homework)

各回で解消しきれなかったチェンジログ行を、次回の冒頭デモに向けた宿題として残す場所。
構造は次の通り:

```
homework/
  YYYYMMDD/              # 開催日（ハイフンなし 8 桁）
    <slug>/              # 宿題 1 件 = 1 ディレクトリ。slug は短いトピック名
      homework.md        # 疑問・調査メモ・使い分け等の writeup
      demo/              # 次回冒頭デモで使う実物を置く
        README.md        # デモ手順書
        ...              # デモ用スクリプト・設定・ログ等
```

- [homework/20260424/agent/](./homework/20260424/agent) — `--agent` の振る舞いと有効な使い方
- [homework/20260519/session-start-agent/](./homework/20260519/session-start-agent)
- [homework/20260616/claude-code-channels/](./homework/20260616/claude-code-channels)

## 毎週の進め方

1. 前回の宿題を冒頭でデモする（各 `homework/<date>/<slug>/demo/` の手順書に沿って実施）
2. [.claude-code-version](./.claude-code-version) の続きから、その回の範囲でアップデートを追いかける
3. 追いついた最新バージョンを [.claude-code-version](./.claude-code-version) に更新する
4. 解消できなかったチェンジログ行を `homework/YYYYMMDD/<slug>/homework.md` として残す（`/add-homework <slug> <changelog line>` で追加）

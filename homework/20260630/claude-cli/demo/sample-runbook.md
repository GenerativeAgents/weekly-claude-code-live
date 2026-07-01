# インシデントランブック: web-gateway の 5xx 急増

deep link の代表的な置き場所が「ランブック」。下の手順 2 を**カスタムスキームを許可する
レンダラ**（社内 wiki, Notion, ブラウザのアドレスバー等）で開くと、対象リポジトリで
Claude Code が起動し、調査プロンプトが**入力済み**で待つ。Enter を押すまで何も送信されない。

> 注意: **GitHub の Markdown は `claude-cli://` を剥がす**ので、GitHub 上ではこのリンクは
> ただのラベルになる。だからこそ URL 全文をコードブロックにも載せておく。

## 手順

1. PagerDuty でページを ack する。
2. [gateway リポジトリで Claude Code を開く](claude-cli://open?repo=acme/web-gateway&q=5xx%20rate%20is%20elevated%20on%20web-gateway.%20Check%20recent%20deploys%2C%20error%20logs%20from%20the%20last%2030%20minutes%2C%20and%20open%20incidents%20in%20Linear.)
   （リンクが効かない環境では次の URL をアドレスバーに貼る）

   ```text
   claude-cli://open?repo=acme/web-gateway&q=5xx%20rate%20is%20elevated%20on%20web-gateway.%20Check%20recent%20deploys%2C%20error%20logs%20from%20the%20last%2030%20minutes%2C%20and%20open%20incidents%20in%20Linear.
   ```
3. 初動を #incident に投稿する。

## シェルから同じリンクを開く（クリックの代わり）

```bash
# macOS
open "claude-cli://open?repo=acme/web-gateway&q=review%20recent%20deploys"
# Linux（要デスクトップ環境 + xdg-open）
xdg-open "claude-cli://open?repo=acme/web-gateway&q=review%20recent%20deploys"
# Windows PowerShell
Start-Process "claude-cli://open?repo=acme/web-gateway&q=review%20recent%20deploys"
```

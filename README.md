# HN Digest

Hacker News から関心に合う記事だけを選び、毎朝読むための個人用アプリです。Mac mini 上で常駐させます。設計の詳細は `docs/design.md` にあります。

## 画面

- `/` は最新のダイジェスト、`/digests/next` は次回確定分である
- `/stories/:id` は記事ページで、要約と日本語訳を出す
- `/labeling` は直近7日の未評価の記事に、キー操作で評価を付ける画面である
- `/profile/edit` はプロファイルの編集と、再採点の結果を確認する

日本語訳だけは、ローカルの ollama ではなく codex CLI(ChatGPT の利用枠)を子プロセスで呼びます。codex は Node 経由で起動するので、Node と codex のログイン済みの環境が前提です。

## 初回セットアップ

ollama を起動し、`qwen3-embedding:4b` と `qwen3.8:27b-mlx` を取得しておきます。

```sh
bundle install
RAILS_ENV=production bin/rails db:prepare db:seed assets:precompile
```

## launchd への登録と解除

plist は `config/launchd/` にあります。Rails が `127.0.0.1:3100` で待ち受け、Solid Queue も同じプロセスで動きます。

```sh
cp config/launchd/com.ug23.hn-digest.plist ~/Library/LaunchAgents/
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.ug23.hn-digest.plist

# 解除
launchctl bootout gui/$(id -u)/com.ug23.hn-digest
rm ~/Library/LaunchAgents/com.ug23.hn-digest.plist
```

## tailscale serve での公開

production は `force_ssl` が有効なので、tailnet 内にだけ HTTPS で公開します。この Mac の 443番は別のアプリが `tailscale serve` で使っているため、8443番を使います。`--https` を付けずに実行すると 443番の設定を上書きするので、付け忘れないでください。

```sh
T=/Applications/Tailscale.app/Contents/MacOS/Tailscale
$T serve --bg --https=8443 http://127.0.0.1:3100
$T serve status

# 公開をやめる
$T serve --https=8443 off
```

公開先は `https://<マシン名>.<tailnet名>.ts.net:8443/` です。

## 更新手順

```sh
git pull
RAILS_ENV=production bin/rails assets:precompile db:prepare
launchctl kickstart -k gui/$(id -u)/com.ug23.hn-digest
```

## 開発時の手動実行

development のジョブは定期実行されません。ジョブは `perform_now` で直接動かします。

```sh
bin/rails runner 'CollectStoriesJob.perform_now'
bin/rails runner 'EvaluateStoryJob.perform_now(Story.first)'
bin/rails runner 'FinalizeDigestJob.perform_now'
bin/rails server -p 3101
```

## システムテスト

ブラウザ操作のテストは `bin/rails test:system` で動かします。ヘッドレスの Google Chrome を使い、`bin/rails test` には含まれません。

## 検証タスクの使い方

モデルの選定には、手採点との一致率を比べる rake タスクを使います。

- `bin/rails eval:sample` は 30 件を選び、`tmp/eval/sample.csv` に書き出す
- CSV の `my_score` と `my_should_read` を手で埋める
- `bin/rails eval:compare MODELS=qwen3.8:27b-mlx,gemma4:26b-mlx` は一致率と順位相関を表で出す
- `EMBED_MODELS=` を渡すと、埋め込みモデルごとの一次フィルタの再現率を出す

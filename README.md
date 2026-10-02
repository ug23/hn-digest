# HN Digest

Hacker News から関心に合う記事だけを選び、毎朝読むための個人用アプリです。Mac mini 上で常駐させます。設計の詳細は `docs/design.md` にあります。

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

production は `force_ssl` が有効なので、tailnet 内にだけ HTTPS で公開します。

```sh
tailscale serve --bg 3100
```

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

## 検証タスクの使い方

モデルの選定には、手採点との一致率を比べる rake タスクを使います。

- `bin/rails eval:sample` は 30 件を選び、`tmp/eval/sample.csv` に書き出す
- CSV の `my_score` と `my_should_read` を手で埋める
- `bin/rails eval:compare MODELS=qwen3.8:27b-mlx,gemma4:26b-mlx` は一致率と順位相関を表で出す
- `EMBED_MODELS=` を渡すと、埋め込みモデルごとの一次フィルタの再現率を出す

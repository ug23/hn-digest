# HN Digest

個人用に作った Rails アプリです。2026年10月の数日だけ運用し、その後に運用を停止しました。設計から実装・レビュー・振り返りまでの記録として公開しています。設計の詳細は `docs/design.md` にあります。

## 作ったもの

Hacker News の記事を毎時集め、関心プロファイルとの類似度とローカル LLM(ollama)で採点します。次の機能を持ちます。

- 毎朝 06:00 に確定するダイジェストと、記事ごとの日本語の要約
- 記事ページでの日本語訳。codex CLI を、読み取りを絞ったサンドボックスの子プロセスとして呼ぶ
- 直近の記事に評価を付けるラベリング画面
- 関心プロファイルの編集と、再採点の結果のプレビュー

採点、要約、埋め込みはローカルの ollama だけを使います。日本語訳だけは、ChatGPT の利用枠で動く codex CLI を使います。

## やめた理由(振り返り)

- 候補が HN のフロントページと同じなので、並べ替えても HN を直接眺めるのに勝てなかった
- 採点を良くする材料はラベリングだが、キーボード前提の操作でスマホから使えず、評価が貯まらなかった。タッチ対応は後から入れたが、運用停止までに使われなかった
- 翻訳は依頼してから1記事あたり数分かかり、実測では 32k 文字の記事が約325秒だった。事前に全件を訳すと、トークンが見合わない
- 次に作るなら「選ぶ」のをやめ、自分で選んだ記事の URL を渡すと要約と訳が用意される道具に絞る

## 作り方

設計(`docs/design.md`)を人間が承認し、実装は AI エージェントへ委譲しました。差分は別のエージェントのレビューと人間の確認を経て取り込んでいます。コミットには `Co-Authored-By` を付けています。

## 画面

- `/` は最新のダイジェスト、`/digests/next` は次回確定分である
- `/stories/:id` は記事ページで、要約と日本語訳を出す
- `/labeling` は直近7日の未評価の記事に、キー操作かタップで評価を付ける画面である
- `/profile/edit` はプロファイルの編集と、再採点の結果を確認する

日本語訳は codex CLI を子プロセスで呼びます。codex は Node 経由で起動するので、Node と codex のログイン済みの環境が前提です。

## セットアップ

ollama を起動し、chat 用と埋め込み用のモデルを1つずつ用意します。開発時に使っていたのは `qwen3.8:27b-mlx`(chat 用)と `qwen3-embedding:4b`(埋め込み用)です。別のモデルを使うときは、環境変数で差し替えます。

```sh
export OLLAMA_CHAT_MODEL=<chat 用のモデル名>
export OLLAMA_EMBED_MODEL=<埋め込み用のモデル名>
export OLLAMA_HOST=http://localhost:11434 # 接続先を変えるときだけ
```

埋め込みモデルを変えたら、記事とプロファイルの埋め込みを作り直す必要があります。プロンプトと一部のパラメータ(`think` など)は、既定のモデル向けに調整してあります。

```sh
bundle install
RAILS_ENV=production bin/rails db:prepare db:seed assets:precompile
```

## launchd への登録と解除(当時の運用例)

雛形は `config/launchd/hn-digest.plist.example` にあります。コピーしたうえで、`YOUR_NAME` を自分のユーザ名に、ラベルを好みの名前に直してください。Rails が `127.0.0.1:3100` で待ち受け、Solid Queue も同じプロセスで動きます。

```sh
cp config/launchd/hn-digest.plist.example ~/Library/LaunchAgents/com.example.hn-digest.plist
# YOUR_NAME を書き換えてから登録する
launchctl bootstrap gui/$(id -u) ~/Library/LaunchAgents/com.example.hn-digest.plist

# 解除
launchctl bootout gui/$(id -u)/com.example.hn-digest
rm ~/Library/LaunchAgents/com.example.hn-digest.plist
```

## tailscale serve での公開(当時の運用例)

production は `force_ssl` が有効なので、tailnet 内にだけ HTTPS で公開しました。当時は 443番を他の用途で使っていたため、8443番にしています。`--https` を付けずに実行すると 443番の設定を上書きするので、付け忘れないでください。

```sh
T=/Applications/Tailscale.app/Contents/MacOS/Tailscale
$T serve --bg --https=8443 http://127.0.0.1:3100
$T serve status

# 公開をやめる
$T serve --https=8443 off
```

公開先は `https://<マシン名>.<tailnet名>.ts.net:8443/` の形になります。

## 更新手順

```sh
git pull
RAILS_ENV=production bin/rails assets:precompile db:prepare
launchctl kickstart -k gui/$(id -u)/com.example.hn-digest
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

## ライセンス

MIT License です。詳細は `LICENSE` を参照してください。

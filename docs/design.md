# HN Digest Design Doc

この文書は2026年10月2日に承認されました。15節の仮置きも、すべてそのまま採用します。

## 1. 目的と全体像

Hacker News(以下 HN)から関心に合う記事だけを選び、日本語の要約と「原文を精読すべきか」の判定を付けて毎朝読みます。個人用で、Mac mini 上に常駐させます。

処理は次の順に流れます。

```text
Algolia HN API ──毎時──> 収集 ──> 本文とコメントの取得 ──> 除外ルール ──> 埋め込みで半分に絞る
                                                                              │
ブラウザ <── 一覧と評価の記録 <── 06:00 に当日分を確定 <── 要約(Phase 2) <── LLM で採点
```

絶対制約は依頼どおりで、この文書の設計はすべてその内側に収めました。

- ランタイムは Ruby だけにする
- 永続化は SQLite だけにし、書き手はこの Rails アプリに限る
- 定期実行は Solid Queue の recurring で行う
- LLM と埋め込みは `http://localhost:11434` の ollama REST だけを使う
- 認証は実装しない

## 2. 環境確認の結果

| 項目 | 結果 |
|---|---|
| macOS | 27.0(26A428)、Apple M6、メモリ 32GB |
| Ruby | システムは 2.6.10。rbenv に 3.3.12 があり、リポジトリの `.ruby-version` で 3.3.12 を指定した |
| Rails | 未導入。最新安定版は 8.1.4 で、Ruby 3.2 以上を要求する |
| SQLite | 3.54.0 |
| ollama | 0.34.4 |
| ポート 3000 | OrbStack が使用中。このアプリは別のポートにする |
| Tailscale | Tailscale.app が導入済み |

非対話シェルの PATH には rbenv の shims が入っていません。launchd の plist では PATH を明示します。

インストール済みの ollama モデルは次の4つです。

| モデル | サイズ | 形式 | 備考 |
|---|---|---|---|
| `qwen3.8:27b-mlx` | 18GB | MLX | thinking は既定で medium。`false` / `low` / `medium` / `xhigh` を選べる |
| `gemma4:26b-mlx` | 18GB | MLX | thinking は既定でオン。`false` にできる |
| `qwen3-coder:30b` | 18GB | GGUF | コード特化 |
| `qwen3-embedding:4b` | 2.5GB | GGUF | 埋め込み専用。2560次元 |

## 3. モデル選定

### 3.1 煙テストの実測

実際の HN 記事を使い、構造化出力が通るかと所要時間だけを見ました。精度の検証ではありません。

| モデルと条件 | 入力 | 所要時間 | 結果 |
|---|---|---|---|
| `qwen3-embedding:4b` | 4文 | 2.3秒(ロード込み) | 2560次元、ノルム 1.0 |
| `qwen3.8:27b-mlx`、think=false | タイトルだけ | 6〜8秒 | 3件とも妥当な JSON |
| `qwen3.8:27b-mlx`、think=false | タイトルとコメント20件(1,311トークン) | 約13秒(ロードを除く) | 妥当な JSON |
| `qwen3.8:27b-mlx`、think=low | 同上 | 28秒 | 妥当な JSON |
| `gemma4:26b-mlx`、think=false、`format` なし | 同上 | 3.5秒 | 妥当な JSON |
| `gemma4:26b-mlx`、think=false、`format` あり | タイトルだけ | 1回目は600秒でタイムアウト、2回目は2.6秒 | 1回目はハング、2回目は妥当な JSON |

分かったことは3点です。

- MLX 版のモデルでは `format`(JSON Schema)の制約を当てにできない。gemma4 のハングは ollama の既知の issue(#16563、#18567)と同じ症状だった。プロンプトに出力キーを書かなかった回でハングし、書いた回では成功した
- タイトルだけの採点は甘くなる。同じ記事にコメントを添えると、qwen3.8 のスコアは 7 から 3 へ、gemma4 は 7 から 4 へ下がった。本文取得に失敗した記事でも、コメントは必ず渡す
- 1日 100件規模なら速度は制約にならない。採点対象が 50件で1件 30秒かかっても、合計 25分で終わる

### 3.2 候補と初期選定

採点用の候補は次の3つです。

| 候補 | 長所 | 短所 |
|---|---|---|
| `qwen3.8:27b-mlx`(think=false か low) | `format` 付きで4回とも通った。理由の文章が具体的 | gemma4 より4〜8倍遅い |
| `gemma4:26b-mlx`(think=false) | 1件 3.5秒と速い | `format` 指定時にハングした実績がある |
| `qwen3-coder:30b` | GGUF なので schema の制約が効く | コード特化で、記事の評価には向かない見込み |

埋め込み用の候補は次の3つです。

| 候補 | 長所 | 短所 |
|---|---|---|
| `qwen3-embedding:4b` | 導入済み。100言語以上に対応し、日本語のプロファイルと英語の記事を直接比べられる | 2560次元で、1件あたり約 10KB を使う |
| `bge-m3` | 約 1.2GB と軽い。多言語対応 | 追加の pull が必要 |
| `embeddinggemma` | 300M と最も軽い | 入力長が 2K トークンまで。追加の pull が必要 |

初期値は、採点を `qwen3.8:27b-mlx`(think=false)、埋め込みを `qwen3-embedding:4b` とします。採点は速度より安定を優先しました。埋め込みは、導入済みで日英をまたげるものを選びました。Phase 2 の要約にも同じ採点モデルを使い、18GB のモデルが入れ替わる待ち時間を避けます。

最終決定は次節の検証で行います。

### 3.3 手採点30件との一致率を比べる手順

Phase 1 に rake タスクを2つ含めます。CSV を介してやり取りするので、DB の書き手は Rails のままです。

1. Phase 1 を2〜3日動かし、評価済みの記事を 150件ほど貯める
2. `bin/rails eval:sample` を実行する。30件を層別で選び、`tmp/eval/sample.csv` へ書き出す。内訳は、採点済みからスコアの高・中・低を各7件、一次フィルタで落ちた記事から9件とする。CSV の列は HN ID、タイトル、記事の URL、HN の URL だけで、モデルのスコアは載せない
3. CSV の `my_score`(1〜10)と `my_should_read`(yes / skim / no)の列を手で埋める
4. `bin/rails eval:compare MODELS=qwen3.8:27b-mlx,gemma4:26b-mlx` を実行する。各モデルで30件を採点し直し、次の指標を表で出す

| 指標 | 意味 | 採用の目安 |
|---|---|---|
| 二値の一致率 | 「スコアが閾値以上か」が手採点と一致した割合 | 80%以上 |
| 取りこぼし | 手採点で閾値以上なのに、モデルが閾値未満とした件数 | 2件以下 |
| should_read の一致率 | 3値がそのまま一致した割合 | 参考値 |
| 順位相関 | スコアのスピアマン順位相関 | 0.6以上 |
| 所要時間 | 1件あたりの平均秒数 | 同点のときの決め手 |
| 一次フィルタの再現率 | 手採点で閾値以上の記事のうち、類似度の上位半分に入った割合 | 90%以上 |

不一致の記事は、差が大きい順に一覧で出します。プロンプトやプロファイルを直す材料にします。埋め込みモデルを比べるときは `EMBED_MODELS=` を渡し、一次フィルタの再現率だけを比べます。

## 4. 構成

### 4.1 Rails 8 の既定構成と、古い Rails との違い

`rails new` の既定をそのまま使います。古い Rails の経験から見て変わった点を表にまとめます。コードにも同じ趣旨のコメントを付けます。

| 用途 | 古い Rails | Rails 8 の既定 | そうなっている理由 |
|---|---|---|---|
| ジョブ | Sidekiq と Redis | Solid Queue | ジョブを DB の行として持つ。SQLite だけで動き、Redis の運用が要らない |
| 定期実行 | cron、whenever | `config/recurring.yml` | Solid Queue のスケジューラが時刻になるとジョブを積む。設定がリポジトリに入る |
| アセット | Sprockets、Webpacker | Propshaft | ファイルにダイジェストを付けて配るだけにした。変換は行わない |
| JavaScript | Webpacker と npm | importmap | ブラウザの ES Modules をそのまま使う。ビルドも Node も要らない |
| 画面の部分更新 | UJS、Turbolinks | Turbo、Stimulus | サーバが HTML の断片を返し、Turbo が差し替える。Stimulus は小さな振る舞いだけを足す |
| WebSocket の中継 | Redis | Solid Cable | メッセージを DB に書き、各プロセスがポーリングで拾う。プロセスをまたいで届く |
| キャッシュ | Redis、Memcached | Solid Cache | 今回は使わないが、既定のまま残す |
| `lib/` の読み込み | 手で require | `config.autoload_lib` | `lib/` 配下も Zeitwerk が自動で読み込む |

### 4.2 プロセス構成

常駐するのは、launchd が起動する Rails プロセス1系統だけです。

```text
launchd
  └─ puma(RAILS_ENV=production、127.0.0.1:3100)
       ├─ Web スレッド          画面と評価の記録
       └─ Solid Queue(Puma プラグイン。SOLID_QUEUE_IN_PUMA=1 で有効になる)
            ├─ scheduler        recurring.yml を見てジョブを積む
            ├─ worker: default  3スレッド。HTTP の取得
            └─ worker: llm      1スレッド。ollama への依頼を直列にする
```

production で動かします。Rails 8 の production は、Solid Queue、Solid Cable、用途別の SQLite ファイルを最初から設定済みです。development の既定はプロセス内の async アダプタで、recurring は動きません。開発中の確認は、コンソールやテストからジョブを `perform_now` で直接実行します。

SQLite のファイルは `storage/` 配下に用途別で4つできます。

| ファイル | 中身 |
|---|---|
| `production.sqlite3` | アプリのデータ |
| `production_queue.sqlite3` | Solid Queue のジョブ |
| `production_cable.sqlite3` | Solid Cable のメッセージ |
| `production_cache.sqlite3` | Solid Cache(未使用) |

Rails 8 は SQLite に WAL、`synchronous=normal`、5秒の busy timeout、即時ロックのトランザクションを既定で設定します。Web とジョブが同時に書いても、この規模では競合しません。

### 4.3 ディレクトリと行数の見積もり

追加する gem は `ruby-readability`(0.7.3)と `pdf-reader`(2.16.0)の2つだけです。Nokogiri は Rails の依存に含まれます。HTTP は標準の `Net::HTTP` を使います。CSS は素の CSS を1ファイルだけ書きます。

| 場所 | ファイル | 役割 | 行数の目安 |
|---|---|---|---|
| `app/models/` | `story.rb` `profile.rb` `evaluation.rb` `feedback.rb` | データと判定ロジック(類似度、除外ルール、スコア補正) | 110 |
| `lib/` | `hn.rb` | Algolia と HN 公式 API の呼び出し | 50 |
| `lib/` | `content_fetcher.rb` | HTML、PDF、GitHub README の本文抽出 | 70 |
| `lib/` | `ollama.rb` | 埋め込みと構造化出力の呼び出し、検証、再試行 | 60 |
| `app/jobs/` | `collect_stories_job.rb` `fetch_story_job.rb` `evaluate_story_job.rb` `finalize_digest_job.rb` | パイプラインの各段 | 110 |
| `app/prompts/` | `score.md.erb` | 採点プロンプト | 行数に数えない |
| `app/controllers/` `app/views/` | `digests` `feedbacks` | 一覧と評価の記録 | 120 |
| `config/` | `queue.yml` `recurring.yml` `routes.rb` と launchd の plist | 設定 | 60 |
| `lib/tasks/` | `eval.rake` | 3.3節の検証 | 行数に数えない |

Phase 1 は約 580行になります。Phase 2 は要約ジョブ、ラベリング画面、プロファイル編集と再採点で約 250行を足し、合計で約 830行を見込みます。上限の 800行をわずかに超える見積もりなので、実装中に超えそうなら削る箇所を相談します。数える対象は手で書く Ruby、ERB、JavaScript、YAML です。`rails new` の生成物、プロンプト、テスト、検証用の rake タスクは含めません。

## 5. データモデル

Phase 1 で作るテーブルは4つです。Phase 2 で `summaries` を足します。

### stories

HN の記事1件が1行になります。本文、コメント、埋め込みはプロファイルに依存しないので、ここに持ちます。

| カラム | 型 | 説明 |
|---|---|---|
| `hn_id` | integer、一意 | HN のアイテム ID。冪等な保存のキー |
| `title` `url` `author` | string | `url` は Ask HN などでは NULL |
| `points` `num_comments` | integer | 収集のたびに更新する |
| `posted_at` | datetime | HN への投稿時刻 |
| `story_text` | text | Ask HN などの本文 |
| `content` | text | 抽出した本文。先頭 20,000文字まで |
| `content_status` | string | `pending` / `fetched` / `failed` |
| `fetch_attempts` | integer | 取得を試みた回数 |
| `retry_after` | datetime | この時刻を過ぎたら再試行する |
| `fetch_error` | string | 直近の失敗理由 |
| `comments` | json | 上位コメントの配列。要素は `{author, text, replies}` |
| `embedding` | binary | float32 のリトルエンディアンを並べた BLOB(`pack("e*")`) |
| `digested_on` | date、索引 | 確定したダイジェストの日付。未確定は NULL |

コメントは別テーブルにしません。LLM への入力としてまとめて読むだけで、1件ずつの検索や更新をしないからです。

### profiles

関心プロファイルの版が1行になります。行は作成後に書き換えません。編集は新しい版の追加として扱い、`version` が最大の行を現行版とします。

| カラム | 型 | 説明 |
|---|---|---|
| `version` | integer、一意 | 1から始まる連番 |
| `description` | text | 自然言語の数段落 |
| `tag_weights` | json | `{"postgresql": 1, "funding": -2}` の形 |
| `excluded_domains` `excluded_keywords` | json | ハードルール |
| `score_threshold` | integer | 初期値 5 |
| `embedding` | binary | `description` の埋め込み |

### evaluations

記事とプロファイル版の組が1行になります。版ごとに行を分けるので、再採点しても過去の結果が残り、Phase 2 で差分を出せます。

| カラム | 型 | 説明 |
|---|---|---|
| `story_id` `profile_id` | 参照、組で一意 | |
| `status` | string | `excluded`(ハードルール) / `filtered`(一次フィルタ) / `scored` |
| `note` | string | 当たった除外ルールなど |
| `similarity` | float | プロファイルとのコサイン類似度 |
| `llm_score` | integer | モデルが返した 1〜10 |
| `score` | integer | タグ別重みで補正した後の 1〜10。一覧と閾値の判定に使う |
| `reasons` `tags` | json | モデルが返した理由とタグ |
| `should_read` | string | `yes` / `skim` / `no` |
| `model` | string | 採点に使ったモデル名 |

### feedbacks

| カラム | 型 | 説明 |
|---|---|---|
| `story_id` | 参照、一意 | 1記事に1件。押し直すと上書きする |
| `rating` | integer | 1(👍)か -1(👎) |
| `reason` | string | 一言の理由。任意 |

### summaries(Phase 2)

`story_id`(一意)、`key_points`(json、3行)、`relevance`(仕事との接点)、`discussion`(HN の論点と反論)、`verdict`(精読すべきか)、`model` を持ちます。

## 6. ジョブ定義

### 6.1 定期実行

`config/recurring.yml` に2つ登録します。Solid Queue が既定で入れる完了ジョブの掃除はそのまま残します。

| ジョブ | スケジュール | 内容 |
|---|---|---|
| `CollectStoriesJob` | 毎時5分 | 収集と、後続ジョブの積み直し |
| `FinalizeDigestJob` | `0 6 * * * Asia/Tokyo` | 当日分のダイジェストを確定する |

### 6.2 CollectStoriesJob

default キューで動き、3つのことをします。

1. Algolia の `search_by_date` を `tags=story`、`numericFilters=points>=30,created_at_i>(48時間前)`、`hitsPerPage=1000` で呼ぶ。`hn_id` をキーに `upsert_all` し、既存の行は `points` と `num_comments` だけを更新する
2. `content_status` が `pending` で、`retry_after` が NULL か過去の記事に `FetchStoryJob` を積む
3. 取得が済んでいて現行プロファイルの評価が無い記事に `EvaluateStoryJob` を積む

投稿直後の記事は points が低いままです。直近48時間を毎回引き直すので、後から閾値を超えた記事も拾えます。2と3は毎時の掃き直しを兼ねます。ollama が止まっていた時間の記事も、次の回で処理されます。

### 6.3 FetchStoryJob

default キューで動き、本文とコメントを取ります。

- 本文は URL の種類で取り方を分ける。`github.com/owner/repo` は GitHub API で README を取る。応答が PDF なら pdf-reader で先頭20ページを読む。それ以外は ruby-readability で本文を抜き、Nokogiri でテキストにする。URL が無い記事は `story_text` を本文にする
- コメントは、HN 公式 API の `kids`(表示順)と Algolia の `items`(全文のツリー)を1回ずつ呼び、上位20件を組み立てる
- 本文の取得に失敗したら `fetch_attempts` を増やし、`retry_after` を1時間後、次は4時間後に設定する。3回失敗したら `failed` として諦め、タイトルとコメントだけで評価へ進む
- 成功か諦めのどちらかで `EvaluateStoryJob` を積む

### 6.4 EvaluateStoryJob

llm キューで動きます。引数は記事とプロファイル版です。同じ組の評価が既にあれば何もしません。

1. ハードルールを当てる。除外ドメインか除外キーワードに当たれば `excluded` で終える
2. 記事の埋め込みが無ければ、タイトルと本文の先頭 1,000文字を埋め込んで保存する
3. プロファイルとのコサイン類似度を Ruby で計算する。基準値を下回れば `filtered` で終える
4. 採点プロンプトを組み立てて ollama に渡す。応答を検証し、`llm_score`、理由、タグ、`should_read` を保存する
5. タグ別重みで補正した `score` を保存する

基準値は、現行プロファイルの直近7日の類似度の中央値とします。件数が30件に満たない間は全件を通します。毎時の回は数件しか無いので、回ごとに半分へ絞ると結果が安定しません。

ollama に繋がらない、応答が検証を通らないといった失敗は、`retry_on` で10分おきに3回まで試します。それでも駄目なら、次の毎時の回が積み直します。

### 6.5 FinalizeDigestJob

default キューで動きます。現行プロファイルで `score` が閾値以上かつ `digested_on` が NULL の記事に、今日の日付を入れます。

最後に `ActiveSupport::Notifications.instrument("digest_finalized.hn_digest", date:, story_ids:)` を1行呼びます。Push 通知は将来ここを購読して足します。今回は購読者を作りません。

### 6.6 Phase 2 で足すジョブ

- `SummarizeStoryJob` は llm キューで動く。採点の直後に、`score` が閾値以上の記事へ積む。本文とコメントから日本語の要約を作る。06:00 の確定までに要約が揃う
- `RescoreJob` は default キューで動く。新しいプロファイル版の埋め込みを作り、過去7日の記事に `EvaluateStoryJob` を積む。記事の埋め込みは保存済みなので、類似度の再計算は Ruby だけで済む。各評価の完了時に Turbo Streams で差分を配信する

## 7. プロンプト設計

プロンプトの本文は `app/prompts/` 配下の ERB ファイルで管理し、変更履歴は git に残します。

### 7.1 採点プロンプト(`score.md.erb`)

システムプロンプトは次の構成にします。

1. 役割。読者1人のために記事を選別する編集者とする
2. 関心プロファイルの `description`
3. 評価軸。次節の5つを明示する
4. スコアの目安。次節の表を載せる
5. `should_read` の定義。`yes` は原文を精読する価値がある、`skim` は要約で足りる、`no` は読まなくてよい
6. タグの語彙。`tag_weights` のキーを列挙し、当てはまるものは同じ綴りで使わせる。語彙に無いタグも自由に足してよい
7. 出力形式。キーと型を文章でも書く

評価軸は次の5つです。

| 評価軸 | 見る点 |
|---|---|
| 関心との適合 | プロファイルの領域に当てはまるか |
| 耐久性 | 数年後も読む価値があるか。原理、設計判断、事後分析、実測を高く見る。速報は低く見る |
| 実務への転用 | 具体的な経験、数値、失敗談があるか |
| 議論の質 | HN のコメントが本文を補強または反証する知見を含むか |
| 減点 | ニュース性だけの記事(資金調達、人事、政治)、宣伝、中身の薄い記事 |

スコアの目安は次のとおりです。

| スコア | 目安 |
|---|---|
| 9〜10 | 必読 |
| 7〜8 | 読む価値あり |
| 5〜6 | 要約で足りる |
| 3〜4 | ほぼ無関係 |
| 1〜2 | ノイズ |

ユーザープロンプトには、タイトル、ドメイン、points、コメント数、本文の先頭 6,000文字、上位コメント20件(各 500文字まで)を入れます。

呼び出しでは `format` に JSON Schema を渡し、`temperature: 0`、`think: false`、`num_ctx: 16384`、`num_predict: 800` を指定します。3.1節のとおり MLX では `format` を当てにできないので、次の4つで守ります。

- プロンプトにも出力キーを書く
- `num_predict` と読み取りタイムアウト(180秒)で暴走を止める
- 応答を Ruby 側で検証する。`score` が 1〜10 の整数か、`should_read` が3値のどれかを見る
- 検証に落ちたら1回だけ再試行する

### 7.2 要約プロンプト(`summarize.md.erb`、Phase 2)

本文の先頭 12,000文字とコメントを渡し、日本語で次の4項目を JSON で返させます。

- `key_points`。3行の要点
- `relevance`。プロファイルに照らした、私の仕事との接点
- `discussion`。HN での主な論点と、それに対する反論
- `verdict`。精読すべきかと、その理由

### 7.3 埋め込みの入力

qwen3-embedding は、検索する側に指示文を付けると精度が上がります。プロファイル側は `Instruct: (読者の関心に合う記事を探す旨の指示)\nQuery: (description)` の形で埋め込みます。記事側はタイトルと本文の冒頭をそのまま埋め込みます。

## 8. 関心プロファイルの初期値

`db/seeds.rb` で第1版を作ります。`description` は次の文章にします。

> バックエンド開発、分散システム、PostgreSQL、JVM、AWS を仕事で扱っています。LLM エージェントを使った開発の実務知見に強い関心があります。ソフトウェアアーキテクチャと組織設計、SaaS の運用にも関心があります。
>
> 読みたいのは、原理や設計判断の解説、障害の事後分析、実測に基づく比較、長く運用した経験の記録です。数年後に読んでも価値が残るかを重視します。
>
> 資金調達、人事、政治のようなニュース性だけの記事は読みません。製品の発表だけで技術的な中身が無い記事も読みません。

タグ別重みは次のとおりとします。

| 重み | タグ |
|---|---|
| +1 | `backend` `distributed-systems` `postgresql` `jvm` `aws` `llm-agents` `software-architecture` `org-design` `saas-ops` `postmortem` |
| -2 | `funding` `personnel` `politics` |
| -1 | `product-announcement` |

ハードルールは、除外ドメインと除外キーワードを空で始めます。スコア閾値は 5 とします。

## 9. 画面

Phase 1 で作るのは1つめの画面だけです。

### 9.1 今日のダイジェスト一覧(Phase 1)

- `/` は最新の確定済みダイジェストを表示する。`/digests/2026-10-03` で日付を指定できる。`/digests/next` は、次の 06:00 に確定する予定の記事を表示する
- `should_read` が `yes` の記事を上にまとめ、その中と残りをスコアの降順で並べる
- 1件の行には、スコア、原文にリンクしたタイトル、HN のリンク、ドメイン、points、タグ、理由を出す。Phase 2 で要約を足す
- 高評価と低評価のボタンは `button_to` の POST にし、1タップで記録する。応答は Turbo Stream で返し、その行の評価欄だけを差し替える。差し替え後の欄に一言理由の入力欄が出る。必要なときだけ書いて Enter で保存する
- `?all=1` を付けると、閾値未満の記事や一次フィルタが落とした記事も薄い色で出す。閾値を低めにして取りこぼしを観察する方針に合わせた表示である

### 9.2 ラベリング画面(Phase 2)

過去7日の未評価の記事を、カード1枚ずつ表示します。カードにはタイトル、要約、コメントの要点を出します。Stimulus のコントローラ1つがキー入力を受け、J と K でカードを移動し、評価のキーでフォームを送信します。

### 9.3 プロファイル編集と再採点プレビュー(Phase 2)

フォームを保存すると新しい版ができ、`RescoreJob` が積まれます。画面には過去7日の記事と旧スコアの表を出しておきます。再評価が1件終わるたびに、ジョブが Turbo Streams で「旧スコア → 新スコア」の行を差し込みます。閾値をまたいだ行は強調します。

## 10. 公開と常駐

- Puma は `127.0.0.1:3100` で待ち受ける。LAN には直接公開しない
- Tailscale の `tailscale serve` で、tailnet 内にだけ HTTPS で公開する。Rails 8 の production は `force_ssl` が既定で有効であり、この形なら設定を変えずに済む
- launchd の plist はリポジトリの `config/launchd/` に置く。`~/Library/LaunchAgents/` への配置と `launchctl` の実行は、手順を示したうえで承認を得てから行う
- 更新の手順は `git pull`、`bin/rails assets:precompile db:prepare`、`launchctl kickstart -k` の3つである。Propshaft は本番でアセットにダイジェストを付けるので、事前のコンパイルが要る

## 11. ファイル境界の方針

- `storage/*.sqlite3` を開くのは、この Rails アプリだけである。Puma、Puma が起動する Solid Queue のプロセス、手作業の `bin/rails console` と rake タスクがこれに当たる。`sqlite3` コマンドや他の言語から書き込まない
- ollama とは HTTP だけでやり取りする。ollama 側に状態を持たせない
- 将来、外部プロセスを足すときは、ファイルの一方向の受け渡しに限る。今回は受け渡し用のディレクトリを作らない
- 3.3節の検証で使う `tmp/eval/sample.csv` は、この方針の最初の例である。Rails が書き出し、人の手で埋めたものを Rails が読む
- プロンプトはファイル(git 管理)に置き、プロファイルは DB(版ごとの行)に置く。プロンプトは開発者が直すもので、プロファイルは画面から直すものだからである

将来の受け渡しは、次の表の形に限ります。

| 向き | 置き場所 | 書き手 | 読み手 |
|---|---|---|---|
| Rails から外部へ | `storage/outbox/` | Rails | 外部プロセス |
| 外部から Rails へ | `storage/inbox/` | 外部プロセス | Rails のジョブ |

書き手は一時ファイル名で書いてからリネームし、書き終えたファイルは変更しません。同じファイルを双方向に使いません。

## 12. テストと動作確認

Rails 既定の Minitest を使い、gem は足しません。テストは外部と通信しない部分に絞ります。

- ベクトルの BLOB への変換とコサイン類似度
- ハードルール、一次フィルタの基準値、タグ別重みによる補正
- Algolia の応答(保存した JSON)から記事の属性への変換
- 評価を記録するコントローラ

HTTP を伴う部分は、Phase の完了時に実データで動かして確認し、その手順を報告に書きます。

## 13. Phase 分け

| Phase | 範囲 |
|---|---|
| Phase 1 | `rails new`、データモデル、収集、本文とコメントの取得、一次フィルタ、採点、ダイジェストの確定とフック、一覧と評価の記録、launchd の plist、検証用の rake タスク |
| Phase 2 | 要約、ラベリング画面、プロファイル編集と再採点プレビュー、評価の蓄積を採点へ反映する仕組み |

## 14. スコープ外

- Push 通知。確定時のフックだけを置く
- 認証と複数ユーザー
- 外部の LLM や埋め込み API
- HN 以外の情報源
- 全文検索、ベクトル検索用の拡張(sqlite-vec など)
- タグ別重みの自動調整
- Kamal、Docker による配備

## 15. 未確定事項

依頼に書かれておらず、推測で埋めた点です。2026年10月2日に、すべて仮置きのとおりで承認されました。

| 番号 | 項目 | 仮置き | 理由と代替 |
|---|---|---|---|
| U1 | `rails new` のオプション | Kamal、Docker、Thruster、Action Mailer、Action Mailbox、Action Text、Active Storage を skip する | Mac mini で直接動かすので使わない。代替は何も skip しない形で、未使用のファイルが残る |
| U2 | 実行環境と公開方法 | production で動かし、`127.0.0.1:3100` と `tailscale serve` で公開する | 4.2節と10節のとおり。代替は `0.0.0.0` で待ち受けて `force_ssl` を外す形だが、LAN にも認証なしで見える |
| U3 | コメントの取得元 | HN 公式 API の `kids` で順位を、Algolia の `items` で本文を取る | Algolia の `items` は作成順で、コメントの points も入らない。これだけでは上位を選べないと実測で確認した。収集は依頼どおり Algolia を使う |
| U4 | コメントに付いた返信 | 上位20件のそれぞれに、返信を先頭2件まで付ける | 「論点と反論」を要約するには返信が要る。追加のリクエストは発生しない |
| U5 | 収集の閾値と窓 | points 30以上、直近48時間 | points が50超だと実測で1日約48件だった。100件規模にするには閾値を下げる必要がある。運用しながら調整する |
| U6 | 「半分に絞る」の定義 | 直近7日の類似度の中央値を基準値とし、30件貯まるまでは全件を通す | 6.4節のとおり |
| U7 | タグ別重みの使い方 | モデルが付けたタグのうち語彙に一致するものの重みを合計し、±2 の範囲に丸めて `llm_score` に足す | 補正の内訳を画面で説明できる。代替は重みをプロンプトに書いてモデルに任せる形で、効き方を追えない |
| U8 | 評価の蓄積を精度へ反映する方法 | Phase 2 で、直近の 👍 と 👎 を理由付きで各5件、採点プロンプトに例として入れる | 最も少ない実装で効く。Phase 1 は記録だけを行う |
| U9 | 「当日分」の定義 | 前回の確定以降に閾値を超えた記事を、06:00 に当日の日付で確定する | 06:00 を過ぎて評価が終わった記事は翌日分に入る |
| U10 | プロファイル保存時の扱い | 保存した時点で新しい版を現行版にする | 戻すときは、旧版の内容を編集画面に読み込んで保存し直す |
| U11 | ラベリング画面のキー | J と K で移動、U で 👍、D で 👎 | 依頼ではキーの割り当てが未指定だった |
| U12 | ollama の共有 | 他のセッションとの排他は行わず、ollama 側の待ち行列に任せる | llm キューは1スレッドなので、このアプリからの同時依頼は1件に収まる |

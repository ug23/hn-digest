# Design Doc 3.3節: 手採点との一致率でモデルを比べる。DB には書かず、CSV を介してやり取りする。
namespace :eval do
  SAMPLE_CSV = Rails.root.join("tmp/eval/sample.csv")

  desc "採点済みを高・中・低で各7件、filtered から9件を選んで tmp/eval/sample.csv に書き出す"
  task sample: :environment do
    require "csv" # Rails の起動時に毎回読まないよう、タスクの中で読む
    profile = Profile.current
    scored = Evaluation.where(profile: profile, status: "scored").includes(:story).order(:score, :id).to_a
    third = (scored.size / 3.0).ceil
    picked = scored.each_slice([ third, 1 ].max).map { |g| g.sample(7) }.flatten
    picked += Evaluation.where(profile: profile, status: "filtered").includes(:story).to_a.sample(9)
    FileUtils.mkdir_p(SAMPLE_CSV.dirname)
    CSV.open(SAMPLE_CSV, "w") do |csv|
      csv << %w[hn_id title url hn_url my_score my_should_read]
      picked.map(&:story).shuffle.each { |s| csv << [ s.hn_id, s.title, s.url, s.hn_url, nil, nil ] }
    end
    puts "#{picked.size} 件を #{SAMPLE_CSV} に書き出した。my_score と my_should_read を埋めること"
  end

  desc "手採点との一致率を比べる。MODELS=a,b EMBED_MODELS=x,y"
  task compare: :environment do
    require "csv"
    profile = Profile.current
    rows = CSV.read(SAMPLE_CSV, headers: true).select { |r| r["my_score"].present? }
    stories = Story.where(hn_id: rows.map { |r| r["hn_id"].to_i }).index_by(&:hn_id)
    mine = rows.to_h { |r| [ r["hn_id"].to_i, { score: r["my_score"].to_i, read: r["my_should_read"] } ] }
    threshold = profile.score_threshold
    spearman = lambda do |a, b|
      rank = ->(v) { v.map { |x| (v.count { |y| y < x } + (v.count { |y| y == x } + 1) / 2.0) } }
      ra = rank.(a)
      rb = rank.(b)
      ma = ra.sum / ra.size
      mb = rb.sum / rb.size
      cov = ra.zip(rb).sum { |x, y| (x - ma) * (y - mb) }
      den = Math.sqrt(ra.sum { |x| (x - ma)**2 } * rb.sum { |y| (y - mb)**2 })
      den.zero? ? Float::NAN : cov / den
    end

    models = ENV.fetch("MODELS", Ollama::CHAT_MODEL).split(",")
    mismatches = []
    puts format("%-24s %8s %8s %10s %8s %8s", "model", "binary", "missed", "should_read", "spearman", "sec/item")
    models.each do |model|
      results = {}
      started = Time.now
      mine.each_key do |hn_id|
        r = Scorer.call(stories[hn_id], profile, model: model)
        results[hn_id] = r.merge(score: profile.adjusted_score(r[:llm_score], r[:tags]))
      rescue Ollama::Error => e
        warn "#{model} #{hn_id}: #{e.message}"
      end
      elapsed = Time.now - started
      ids = results.keys
      n = ids.size
      next puts("#{model}: 採点できた件数が0") if n.zero?

      binary = ids.count { |i| (results[i][:score] >= threshold) == (mine[i][:score] >= threshold) }
      missed = ids.count { |i| mine[i][:score] >= threshold && results[i][:score] < threshold }
      read = ids.count { |i| results[i][:should_read] == mine[i][:read] }
      rho = spearman.(ids.map { |i| results[i][:score] }, ids.map { |i| mine[i][:score] })
      puts format("%-24s %7.0f%% %8d %9.0f%% %8.2f %8.1f", model, 100.0 * binary / n, missed, 100.0 * read / n, rho, elapsed / n)
      ids.each { |i| mismatches << [ (results[i][:score] - mine[i][:score]).abs, model, stories[i].title, mine[i][:score], results[i][:score] ] }
    end

    puts "\n不一致(差の大きい順)"
    mismatches.select { |m| m[0] >= 2 || (m[3] >= threshold) != (m[4] >= threshold) }.sort_by { |m| -m[0] }.each do |diff, model, title, my, model_score|
      puts format("  差%d  手採点 %d / %s %d  %s", diff, my, model, model_score, title)
    end

    # 一次フィルタの再現率: 手採点で閾値以上の記事が、類似度の上位半分に入った割合
    ENV["EMBED_MODELS"].to_s.split(",").each do |model|
      query = Ollama.embed([ EvaluateStoryJob::QUERY_PREFIX + profile.description ], model: model).first
      list = mine.keys.map { |i| [ i, Embeddable.cosine(Ollama.embed([ stories[i].embed_text ], model: model).first, query) ] }
      top = list.sort_by { |_, sim| -sim }.first((list.size / 2.0).ceil).map(&:first)
      wanted = mine.keys.select { |i| mine[i][:score] >= threshold }
      puts format("埋め込み %-24s 再現率 %s", model, wanted.empty? ? "n/a" : format("%.0f%% (%d/%d)", 100.0 * (wanted & top).size / wanted.size, (wanted & top).size, wanted.size))
    end
  end
end

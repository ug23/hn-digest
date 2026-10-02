# 第1版の関心プロファイル（Design Doc 8節）。version で探すので何度実行しても増えない。
Profile.find_or_create_by!(version: 1) do |p|
  p.description = <<~TEXT
    バックエンド開発、分散システム、PostgreSQL、JVM、AWS を仕事で扱っています。LLM エージェントを使った開発の実務知見に強い関心があります。ソフトウェアアーキテクチャと組織設計、SaaS の運用にも関心があります。

    読みたいのは、原理や設計判断の解説、障害の事後分析、実測に基づく比較、長く運用した経験の記録です。数年後に読んでも価値が残るかを重視します。

    資金調達、人事、政治のようなニュース性だけの記事は読みません。製品の発表だけで技術的な中身が無い記事も読みません。
  TEXT
  p.tag_weights = {
    "backend" => 1, "distributed-systems" => 1, "postgresql" => 1, "jvm" => 1, "aws" => 1,
    "llm-agents" => 1, "software-architecture" => 1, "org-design" => 1, "saas-ops" => 1, "postmortem" => 1,
    "funding" => -2, "personnel" => -2, "politics" => -2,
    "product-announcement" => -1
  }
  p.score_threshold = 5
end

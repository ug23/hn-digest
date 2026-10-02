module ApplicationHelper
  # 評価の表示。採点済みならスコア、そうでなければ status。まだ無ければ「待ち」
  def evaluation_label(evaluation)
    return "待ち" unless evaluation

    evaluation.status == "scored" ? evaluation.score : evaluation.status
  end

  def key_points_list(summary)
    tag.ul(safe_join(summary.key_points.map { |point| tag.li(point) }), class: "key-points")
  end

  def tag_list(tags)
    tag.div(safe_join(tags.map { |t| tag.span(t) }), class: "tags") if tags.any?
  end

  def should_read_badge(evaluation)
    tag.span(evaluation.should_read, class: "badge #{evaluation.should_read}")
  end
end

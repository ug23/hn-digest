class FeedbacksController < ApplicationController
  def create
    story = Story.find(params[:story_id])
    # 評価（rating）と一言理由（reason）は別々に送られてくる。送られた方だけを上書きする
    attrs = {}
    attrs[:rating] = params[:rating].to_i if params[:rating].present?
    attrs[:reason] = params[:reason].to_s.strip.presence if params.key?(:reason)

    if save_feedback(story, attrs)
      story.reload # 評価欄の再描画で story.feedback が最新になるようにする
      respond_to do |format|
        # Turbo Stream で、その行の評価欄（dom_id が付いた要素）だけを差し替える
        format.turbo_stream { render turbo_stream: turbo_stream.replace(helpers.dom_id(story, :feedback), partial: "feedbacks/feedback", locals: { story: story }) }
        format.html { redirect_back fallback_location: root_path } # Turbo が無い場合のフォールバック
      end
    else
      head :unprocessable_entity
    end
  end

  private

  def save_feedback(story, attrs)
    return true if story.feedback.nil? && attrs.values.all?(&:nil?) # 評価も理由も空なら作らない(画面は次へ進んでよい)
    (story.feedback || story.build_feedback).update(attrs)
  rescue ActiveRecord::RecordNotUnique # 二重タップで同時に作られて一意索引に当たった場合は、既存の行を更新する
    story.reload.feedback.update(attrs)
  end
end

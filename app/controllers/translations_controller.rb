class TranslationsController < ApplicationController
  def create
    story = Story.find(params[:story_id])
    translation = Translation.find_or_initialize_by(story: story)
    # 本文が無い、翻訳中(止まっていないもの)、完了済みなら積まない(二重押し対策)。
    # それ以外は、ジョブが始まる前から画面に「翻訳中」を出すため先に running にする
    active = translation.persisted? && (translation.status == "done" || (translation.status == "running" && !translation.stale?))
    if story.body_text && !active
      translation.update!(status: "running", segments: [], error: nil)
      TranslateStoryJob.perform_later(story)
    end
    redirect_to story_path(story)
  end
end

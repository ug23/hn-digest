class ProfilesController < ApplicationController
  def edit
    @profile = Profile.current
    @form = @profile.form_values
    load_rescore
  end

  # プロファイルの行は不変なので、更新ではなく「現行版 +1」の新しい版を作る
  def update
    @form = params.expect(profile: [ :description, :tag_weights, :excluded_domains, :excluded_keywords, :score_threshold ]).to_h.symbolize_keys
    begin
      candidate = Profile.next_from_form(@form)
      return render_invalid(candidate.errors.full_messages.to_sentence) unless candidate.save
    rescue ArgumentError => e
      return render_invalid(e.message)
    end

    RescoreJob.perform_later(candidate)
    redirect_to edit_profile_path
  end

  private

  def render_invalid(message)
    @profile = Profile.current
    @error = message
    load_rescore
    render :edit, status: :unprocessable_entity
  end

  # 再採点の表: 直近7日に投稿された記事のうち、前の版の評価がある記事を新しい順に
  def load_rescore
    return unless (previous = @profile.previous)

    @olds = Evaluation.includes(:story, :profile).where(profile: previous, stories: { posted_at: 7.days.ago.. })
                      .order("stories.posted_at DESC")
    @news = Evaluation.includes(:profile).where(profile: @profile, story_id: @olds.map(&:story_id)).index_by(&:story_id)
  end
end

class DigestsController < ApplicationController
  rescue_from Date::Error, with: -> { head :not_found }

  def show
    @profile = Profile.current
    dates = Story.where.not(digested_on: nil).distinct.order(:digested_on).pluck(:digested_on)
    @next = params[:date] == "next" || (params[:date].nil? && dates.empty?)
    @date = @next ? nil : (params[:date] ? Date.iso8601(params[:date]) : dates.last)
    @prev_date = dates.reverse.find { |d| @next || d < @date }
    @next_date = dates.find { |d| !@next && d > @date }

    # 確定済みの日はその日の記事、next は未確定で閾値以上の記事
    scored = Evaluation.includes(story: :feedback).where(profile: @profile, status: "scored")
    scored = if @next
      scored.joins(:story).where(stories: { digested_on: nil }).where("evaluations.score >= ?", @profile.score_threshold)
    else
      scored.joins(:story).where(stories: { digested_on: @date })
    end
    # should_read が yes のものを上にまとめ、それぞれスコアの降順
    @evaluations = scored.sort_by { |e| [ e.should_read == "yes" ? 0 : 1, -e.score ] }
    @others = others(@evaluations) if params[:all] == "1"
  end

  private

  # ?all=1 用。その日の窓（前日 06:00 から当日 06:00。next は直近の 06:00 以降）に評価された、一覧に載らなかった記事
  def others(shown)
    window_end = @next ? Time.current : @date.in_time_zone.change(hour: 6)
    window_start = @next ? latest_six_am : window_end - 1.day
    Evaluation.includes(story: :feedback).where(profile: @profile, created_at: window_start..window_end)
              .where.not(id: shown.map(&:id)).sort_by { |e| [ -(e.score || 0), -(e.similarity || 0) ] }
  end

  def latest_six_am
    six = Time.current.change(hour: 6)
    six > Time.current ? six - 1.day : six
  end
end

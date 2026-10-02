class StoriesController < ApplicationController
  def show
    @story = Story.includes(:summary, :translation).find(params[:id])
    @evaluation = Evaluation.find_by(story: @story, profile: Profile.current)
  end
end

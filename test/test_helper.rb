ENV["RAILS_ENV"] ||= "test"
require_relative "../config/environment"
require "rails/test_help"

module ActiveSupport
  class TestCase
    parallelize(workers: :number_of_processors)

    def build_profile(**attrs)
      Profile.create!({ version: (Profile.maximum(:version) || 0) + 1, description: "d" }.merge(attrs))
    end

    def build_story(**attrs)
      @seq = (@seq || 0) + 1
      Story.create!({ hn_id: @seq + rand(1_000_000) * 100, title: "Title #{@seq}", url: "https://example.com/#{@seq}" }.merge(attrs))
    end
  end
end

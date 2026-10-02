require "test_helper"

class HnTest < ActiveSupport::TestCase
  def hits
    JSON.parse(file_fixture("hn_hits.json").read)["hits"]
  end

  test "story_attributes は url のある hit を変換する" do
    attrs = Hn.story_attributes(hits[0])
    assert_equal 100, attrs[:hn_id]
    assert_equal "https://www.example.com/pg", attrs[:url]
    assert_equal 120, attrs[:points]
    assert_equal Time.at(1790000000).utc, attrs[:posted_at]
    assert_nil attrs[:story_text]
  end

  test "story_attributes は url の無い Ask HN を変換する" do
    attrs = Hn.story_attributes(hits[1])
    assert_nil attrs[:url]
    assert_equal "First line\n\nSecond & third", attrs[:story_text]
    assert_equal "news.ycombinator.com", Story.new(url: attrs[:url]).domain
  end
end

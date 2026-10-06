require "test_helper"

class StoryTest < ActiveSupport::TestCase
  test "link_url は http/https の URL だけをそのまま返す" do
    assert_equal "https://example.com/a", build_story(url: "https://example.com/a").link_url
    assert_equal "http://example.com/a", build_story(url: "http://example.com/a").link_url
  end

  test "link_url は http/https 以外・不正・空の URL では HN の記事ページを返す" do
    [ "javascript:alert(1)", "data:text/html,x", "http://exa mple.com/x y", "https:///x", nil ].each do |url|
      story = build_story(url: url)
      assert_equal story.hn_url, story.link_url, url.inspect
    end
  end
end

require "test_helper"

class ProfileTest < ActiveSupport::TestCase
  test "exclusion_note は除外ドメインの一致と後方一致を見る" do
    profile = build_profile(excluded_domains: [ "example.com" ])
    assert_match "example.com", profile.exclusion_note(build_story(url: "https://www.example.com/a"))
    assert_match "example.com", profile.exclusion_note(build_story(url: "https://blog.example.com/a"))
    assert_nil profile.exclusion_note(build_story(url: "https://notexample.com/a"))
  end

  test "exclusion_note は除外キーワードを大小無視でタイトルから探す" do
    profile = build_profile(excluded_keywords: [ "Funding" ])
    assert_match "Funding", profile.exclusion_note(build_story(title: "Startup raises FUNDING round"))
    assert_nil profile.exclusion_note(build_story(title: "Postgres tips"))
  end

  test "similarity_cutoff は30件未満なら nil、以上なら中央値" do
    profile = build_profile
    29.times { |i| Evaluation.create!(story: build_story, profile: profile, status: "filtered", similarity: i / 100.0) }
    assert_nil profile.similarity_cutoff
    Evaluation.create!(story: build_story, profile: profile, status: "filtered", similarity: 0.29)
    assert_in_delta 0.145, profile.similarity_cutoff # 0..29 の偶数個の中央値
  end

  test "similarity_cutoff は7日より古い評価を数えない" do
    profile = build_profile
    30.times { Evaluation.create!(story: build_story, profile: profile, status: "filtered", similarity: 0.5, created_at: 8.days.ago) }
    assert_nil profile.similarity_cutoff
  end

  test "adjusted_score は語彙に一致するタグの重みを ±2 に丸めて足す" do
    profile = build_profile(tag_weights: { "a" => 1, "b" => 1, "c" => 1, "x" => -2, "y" => -2 })
    assert_equal 6, profile.adjusted_score(5, %w[a unknown])
    assert_equal 7, profile.adjusted_score(5, %w[a b c])
    assert_equal 1, profile.adjusted_score(2, %w[x y])
    assert_equal 10, profile.adjusted_score(10, %w[a])
    assert_equal 5, profile.adjusted_score(5, [])
  end

  test "current は version が最大の行" do
    build_profile
    latest = build_profile
    assert_equal latest, Profile.current
  end
end

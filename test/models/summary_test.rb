require "test_helper"

class SummaryTest < ActiveSupport::TestCase
  GOOD = { "key_points" => %w[a b c], "relevance" => "r", "discussion" => "d", "verdict" => "v" }.freeze

  test "valid_result? は key_points が文字列3件で、他が空でない文字列なら true" do
    assert Summary.valid_result?(GOOD)
  end

  test "valid_result? は件数や型や空文字を弾く" do
    assert_not Summary.valid_result?(GOOD.merge("key_points" => %w[a b]))
    assert_not Summary.valid_result?(GOOD.merge("key_points" => %w[a b c d]))
    assert_not Summary.valid_result?(GOOD.merge("key_points" => [ "a", "b", 3 ]))
    assert_not Summary.valid_result?(GOOD.merge("key_points" => [ "a", "b", "" ]))
    assert_not Summary.valid_result?(GOOD.merge("relevance" => ""))
    assert_not Summary.valid_result?(GOOD.merge("verdict" => nil))
    assert_not Summary.valid_result?(GOOD.except("discussion"))
  end
end

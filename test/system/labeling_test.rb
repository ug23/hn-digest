require "application_system_test_case"

class LabelingTest < ApplicationSystemTestCase
  test "J/K で移動し、U で理由欄へ移って Enter で保存し次へ進む" do
    profile = build_profile
    %w[Alpha Beta].each_with_index do |title, i|
      Evaluation.create!(story: build_story(title: title), profile: profile, status: "scored", score: 8, llm_score: 8, created_at: i.minutes.ago)
    end
    visit labeling_path
    assert_selector "article.card", count: 1, text: "Alpha"

    send_keys "j"
    assert_selector "article.card", count: 1, text: "Beta"
    send_keys "k"
    assert_selector "article.card", count: 1, text: "Alpha"

    send_keys "u"
    assert_selector "article.card:not([hidden]) input[name=reason]:focus"
    send_keys "jkud" # 理由欄では文字として入力される
    assert_field "reason", with: "jkud"
    send_keys :enter

    assert_selector "article.card", count: 1, text: "Beta"
    # 次のカードへは送信開始の時点で進むので、保存が終わるまで待つ
    wait_until { Feedback.exists?(story: Story.find_by!(title: "Alpha"), rating: 1, reason: "jkud") }

    send_keys "d" # 次のカードでも続けてショートカットが効く
    assert_selector "article.card:not([hidden]) input[name=reason]:focus"
    wait_until { Feedback.exists?(story: Story.find_by!(title: "Beta"), rating: -1) }
  end

  private
    def wait_until
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until yield }
    end
end

require "application_system_test_case"

class LabelingTest < ApplicationSystemTestCase
  teardown { page.driver.browser.manage.window.resize_to(1400, 1400) } # タッチのテストが縮めた分を戻す

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

  test "タッチ操作だけで評価・移動・理由の保存ができ、長いカードでも操作部が見える" do
    page.driver.browser.manage.window.resize_to(390, 844)
    profile = build_profile
    %w[Alpha Beta].each_with_index do |title, i|
      story = build_story(title: title)
      Summary.create!(story: story, key_points: Array.new(30) { |n| "長い要点 #{n} " * 8 }, discussion: "論点") if title == "Alpha"
      Evaluation.create!(story: story, profile: profile, status: "scored", score: 8, llm_score: 8, created_at: i.minutes.ago)
    end
    alpha = Story.find_by!(title: "Alpha")
    visit labeling_path
    assert_selector "article.card", count: 1, text: "Alpha"

    # 長い要約でも、評価ボタンと「次へ」がスクロールなしでビューポートに収まる
    assert page.evaluate_script("document.documentElement.scrollHeight > innerHeight")
    [ "article:not([hidden]) button[data-rating='1']", ".labeling-nav button:last-child" ].each do |selector|
      assert page.evaluate_script("(() => { const r = document.querySelector(\"#{selector}\").getBoundingClientRect(); return r.top >= 0 && r.bottom <= innerHeight && r.height >= 44 })()"), selector
    end
    page.save_screenshot(Rails.root.join("tmp/labeling_390x844.png"))

    find("article:not([hidden]) button[data-rating='1']").click
    wait_until { Feedback.exists?(story: alpha, rating: 1) }
    assert_selector "article.card", count: 1, text: "Alpha" # 進まない
    assert_selector "article:not([hidden]) button.on[data-rating='1']"
    assert_no_selector "input:focus"

    click_button "次へ"
    assert_selector "article.card", count: 1, text: "Beta"
    click_button "前へ"
    assert_selector "article.card", count: 1, text: "Alpha"
    assert_equal 1, Feedback.count # 移動では何も保存されない

    find("article:not([hidden]) input[name=reason]").fill_in with: "タップで保存"
    click_button "保存して次へ"
    assert_selector "article.card", count: 1, text: "Beta"
    wait_until { Feedback.exists?(story: alpha, rating: 1, reason: "タップで保存") }
    assert_no_selector "input:focus"

    # 理由を先に書いてから評価をタップしても、入力は消えない
    find("article:not([hidden]) input[name=reason]").fill_in with: "先に書いた理由"
    find("article:not([hidden]) button[data-rating='-1']").click
    assert_selector "article:not([hidden]) button.on[data-rating='-1']" # 評価欄の差し替えを待つ
    assert_field "reason", with: "先に書いた理由"
    click_button "保存して次へ"
    wait_until { Feedback.exists?(story: Story.find_by!(title: "Beta"), rating: -1, reason: "先に書いた理由") }

    # 保存済みの理由を空に消してから評価しても、空のまま残る
    click_button "前へ"
    find("article:not([hidden]) input[name=reason]").fill_in with: ""
    find("article:not([hidden]) button[data-rating='1']").click
    assert_selector "article:not([hidden]) button.on[data-rating='1']"
    assert_field "reason", with: ""
  end

  private
    def wait_until
      Timeout.timeout(Capybara.default_max_wait_time) { sleep 0.05 until yield }
    end
end

require "test_helper"

class ApplicationSystemTestCase < ActionDispatch::SystemTestCase
  driven_by :selenium, using: :headless_chrome, screen_size: [ 1400, 1400 ]

  setup do
    # Turbo Streams は cable.yml の test(async)で配信する。ジョブは同期的(inline)に動かす。
    # 画面の購読が済んでから配信させたい場面では、各テストで perform_later を止めて perform_now を自分で呼ぶ
    @queue_adapter = ActiveJob::Base.queue_adapter
    ActiveJob::Base.queue_adapter = :inline
  end

  # Minitest 6 には stub が無いので、クラスメソッドを一時的に差し替える(既存のジョブのテストと同じ方法)
  def stub_method(klass, name, impl)
    original = klass.method(name)
    klass.define_singleton_method(name, &impl)
    yield
  ensure
    klass.define_singleton_method(name, original)
  end

  teardown { ActiveJob::Base.queue_adapter = @queue_adapter }
end

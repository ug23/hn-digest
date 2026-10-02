require "test_helper"

class ContentFetcherTest < ActiveSupport::TestCase
  test "内部アドレスは拒否する" do
    %w[127.0.0.1 ::1 ::ffff:127.0.0.1 ::ffff:169.254.169.254 10.0.0.1 100.100.100.100 0.0.0.0 fd7a:115c:a1e0::1].each do |ip|
      assert_not ContentFetcher.public_ip?(ip), "#{ip} は拒否されるべき"
    end
  end

  test "公開アドレスは許可する" do
    %w[93.184.216.34 2606:4700::1111].each { |ip| assert ContentFetcher.public_ip?(ip), "#{ip} は許可されるべき" }
  end

  test "br と td も段落の区切りにする" do
    assert_equal "a\n\nb\n\nc\n\nd", ContentFetcher.paragraphs("<div>a<br>b<table><tr><td>c</td><td>d</td></tr></table></div>")
  end

  test "不正な URL は Error に包む" do
    assert_raises(ContentFetcher::Error) { ContentFetcher.fetch("http://exa mple.com/x y") }
  end
end

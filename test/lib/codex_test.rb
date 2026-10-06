require "test_helper"

class CodexTest < ActiveSupport::TestCase
  # codex の代わりに、与えたシェルスクリプトを呼ばせる(Codex.executable の差し替え)
  def with_script(body)
    Dir.mktmpdir do |dir|
      path = File.join(dir, "fake-codex")
      File.write(path, "#!/bin/sh\n#{body}\n")
      File.chmod(0o755, path)
      original = Codex.executable
      Codex.executable = path
      yield
    ensure
      Codex.executable = original
    end
  end

  test "標準入力のプロンプトを受け取り、out.md の訳文を返す" do
    with_script('cat > /dev/null; printf "  訳文です\n" > out.md') do
      assert_equal "訳文です", Codex.run("prompt")
    end
  end

  test "引数は ARGS のとおり渡る" do
    with_script('echo "$@" >&2; exit 1') do
      error = assert_raises(Codex::Error) { Codex.run("prompt") }
      assert_includes error.message, "--skip-git-repo-check"
      assert_includes error.message, "-o out.md -"
      assert_not_includes error.message, " -m " if Codex::MODEL_NAME.nil?
    end
  end

  test "終了コードが0以外なら標準エラーの末尾つきで Error" do
    with_script('echo "quota exceeded" >&2; exit 3') do
      error = assert_raises(Codex::Error) { Codex.run("prompt") }
      assert_match(/終了コード 3/, error.message)
      assert_match(/quota exceeded/, error.message)
    end
  end

  test "out.md が無い、または空なら Error" do
    with_script("exit 0") { assert_raises(Codex::Error) { Codex.run("prompt") } }
    with_script(": > out.md") { assert_raises(Codex::Error) { Codex.run("prompt") } }
  end

  test "タイムアウトしたら子プロセスを止めて Error" do
    with_script("sleep 30") do
      started = Process.clock_gettime(Process::CLOCK_MONOTONIC)
      error = assert_raises(Codex::Error) { Codex.run("prompt", timeout: 1) }
      assert_match(/タイムアウト/, error.message)
      assert_operator Process.clock_gettime(Process::CLOCK_MONOTONIC) - started, :<, 10
    end
  end

  test "タイムアウトでは孫プロセスも残らない" do
    Dir.mktmpdir do |dir|
      pidfile = File.join(dir, "pid")
      with_script("sleep 30 &\necho \$! > #{pidfile}\nwait") do
        assert_raises(Codex::Error) { Codex.run("prompt", timeout: 1) }
      end
      pid = File.read(pidfile).to_i
      gone = 20.times.any? { Process.kill(0, pid) && (sleep 0.1; false) rescue true }
      assert gone, "孫プロセス #{pid} が残っている"
    end
  end

  test "実行ファイルが無ければ Error" do
    original = Codex.executable
    Codex.executable = "/nonexistent/codex"
    assert_raises(Codex::Error) { Codex.run("prompt") }
  ensure
    Codex.executable = original
  end
end

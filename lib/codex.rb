require "tmpdir"

# 翻訳だけは、ローカルの ollama ではなく codex CLI(ChatGPT の利用枠)を子プロセスで呼ぶ(Design Doc 16.3節、承認済みの例外)。
#
# 記事の本文は信頼できない入力で、codex はコマンド実行などのツールを持つエージェントである。
# 本文に紛れた指示に従わされても被害が出ないよう、次の対策を重ねる。
#   - 空の一時ディレクトリを作業ディレクトリにする(読ませたいものを何も置かない)
#   - sandbox の permissions プロファイルで、読み取りを最小限に絞り、書き込みとネットワークを止める
#   - プロンプトで、本文はデータであり中の指示に従わないと明示する(translate.md.erb)
#   - 訳文は画面に表示するだけで、コマンドやコードとして扱わない
# 残るリスク: exec などのツール自体は無効にできない。ただし sandbox が読み取りを最小限・書き込み不可・ネットワーク遮断にする。
#
# 受け渡しはファイル2つ。プロンプトは Rails が prompt.md に書いて CLI が読み、訳文は CLI が out.md に書いて Rails が読む。CLI は DB に触れない。
module Codex
  class Error < StandardError; end

  # テストで小さなシェルスクリプトに差し替えられるよう、実行ファイルは書き換え可能にしてある
  mattr_accessor :executable, default: "/opt/homebrew/bin/codex"

  # 速いモデル(gpt-5.6-luna)は約45%速いが、技術用語の誤訳が出たため既定モデルを使う(nil なら -m を付けない)。
  # 試すときはここにモデル名を入れる
  MODEL_NAME = nil

  ARGS = [
    "exec",
    "--skip-git-repo-check", # git 管理外の一時ディレクトリで動かす
    "--ephemeral", # セッションファイルを ~/.codex/sessions に残さない
    "--ignore-user-config", # ~/.codex/config.toml の MCP サーバなどを読まない(認証は別ファイルなので使える)
    "--ignore-rules",
    "--color", "never",
    *(MODEL_NAME ? [ "-m", MODEL_NAME ] : []),
    "-c", 'default_permissions="tr"',
    "-c", 'permissions.tr.filesystem={":minimal"="read"}', # 読み取りを最小限に絞る(~/.ssh などは読めない)。書き込みとネットワークも不可
    "-c", 'web_search="disabled"',
    "-c", 'model_reasoning_effort="low"',
    "-o", "out.md", # 最後のメッセージ(訳文)をこのファイルに書かせる
    "-" # プロンプトを標準入力から読む
  ].freeze
  MODEL = "codex (reasoning low)".freeze

  module_function

  def run(prompt, timeout: 300)
    Dir.mktmpdir("codex-") do |dir|
      File.write(File.join(dir, "prompt.md"), prompt)
      stderr_path = File.join(dir, "stderr.log")
      # 配列で渡すのでシェルを介さない。pgroup: true は、孫プロセスごとグループで止めるため
      pid = Process.spawn(executable, *ARGS, chdir: dir, in: File.join(dir, "prompt.md"), out: File::NULL, err: stderr_path, pgroup: true)
      waiter = Process.detach(pid) # 終了を待つスレッド。子プロセスを回収するので、ゾンビが残らない
      status = nil
      begin
        status = waiter.value if waiter.join(timeout)
      ensure
        stop(pid, waiter) if waiter.alive? # タイムアウトのほか、例外や worker の停止で抜けるときも codex を孤児にしない
      end
      stderr_tail = File.exist?(stderr_path) ? File.read(stderr_path).to_s.strip.last(300) : ""
      raise Error, "codex が #{timeout}秒でタイムアウトした: #{stderr_tail}" unless status
      raise Error, "codex が終了コード #{status.exitstatus} で失敗: #{stderr_tail}" unless status.success?

      out = File.join(dir, "out.md")
      text = File.exist?(out) ? File.read(out).strip : ""
      raise Error, "codex の出力が空: #{stderr_tail}" if text.empty?

      text
    end
  rescue SystemCallError => e # 実行ファイルが無い、など
    raise Error, "codex を起動できない: #{e.message}"
  end

  # プロセスグループへ TERM を送り、数秒待って残っていれば KILL
  def stop(pid, waiter)
    Process.kill("TERM", -pid)
    Process.kill("KILL", -pid) unless waiter.join(5)
    waiter.join
  rescue Errno::ESRCH
    nil # 既に終了していた
  end
end

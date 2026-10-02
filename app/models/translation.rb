class Translation < ApplicationRecord
  belongs_to :story

  # worker の再起動や強制終了で running のまま取り残された翻訳。まとまりごとに updated_at が進むので、15分動きが無ければ止まっているとみなす
  def stale?
    status == "running" && updated_at < 15.minutes.ago
  end
end

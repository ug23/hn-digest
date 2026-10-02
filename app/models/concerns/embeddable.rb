# embedding カラム（BLOB）と Ruby の float 配列の相互変換、およびコサイン類似度。
# ベクトル検索用の拡張は使わず、BLOB に float32 を並べて Ruby で計算する（Design Doc 5節）。
module Embeddable
  extend ActiveSupport::Concern

  def embedding_vector
    embedding&.unpack("e*")
  end

  def embedding_vector=(vector)
    self.embedding = vector&.pack("e*")
  end

  def self.cosine(a, b)
    dot = a.zip(b).sum { |x, y| x * y }
    dot / (Math.sqrt(a.sum { |x| x * x }) * Math.sqrt(b.sum { |y| y * y }))
  end
end

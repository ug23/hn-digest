require "test_helper"

class EmbeddableTest < ActiveSupport::TestCase
  test "ベクトルは BLOB へ往復できる" do
    story = build_story
    story.embedding_vector = [ 0.5, -1.25, 3.0 ]
    story.save!
    assert_equal [ 0.5, -1.25, 3.0 ], story.reload.embedding_vector
    assert_equal 12, story.embedding.bytesize
  end

  test "embedding が無ければ nil" do
    assert_nil build_story.embedding_vector
  end

  test "コサイン類似度" do
    assert_in_delta 1.0, Embeddable.cosine([ 1, 2, 3 ], [ 2, 4, 6 ])
    assert_in_delta 0.0, Embeddable.cosine([ 1, 0 ], [ 0, 1 ])
    assert_in_delta(-1.0, Embeddable.cosine([ 1, 0 ], [ -1, 0 ]))
  end
end

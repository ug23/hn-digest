class CreateSummaries < ActiveRecord::Migration[8.1]
  def change
    create_table :summaries do |t|
      t.references :story, null: false, foreign_key: true, index: { unique: true }
      t.json :key_points, null: false, default: []
      t.text :relevance
      t.text :discussion
      t.text :verdict
      t.string :model
      t.timestamps
    end
  end
end

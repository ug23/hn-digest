class CreateEvaluations < ActiveRecord::Migration[8.1]
  def change
    create_table :evaluations do |t|
      t.references :story, null: false, foreign_key: true
      t.references :profile, null: false, foreign_key: true
      t.string :status, null: false
      t.string :note
      t.float :similarity
      t.integer :llm_score
      t.integer :score
      t.json :reasons, null: false, default: []
      t.json :tags, null: false, default: []
      t.string :should_read
      t.string :model
      t.timestamps
    end
    add_index :evaluations, [ :story_id, :profile_id ], unique: true
  end
end

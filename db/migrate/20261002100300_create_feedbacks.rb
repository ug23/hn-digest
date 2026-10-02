class CreateFeedbacks < ActiveRecord::Migration[8.1]
  def change
    create_table :feedbacks do |t|
      t.references :story, null: false, foreign_key: true, index: { unique: true }
      t.integer :rating
      t.string :reason
      t.timestamps
    end
  end
end

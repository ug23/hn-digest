class CreateStories < ActiveRecord::Migration[8.1]
  def change
    create_table :stories do |t|
      t.integer :hn_id, null: false
      t.string :title, null: false
      t.string :url
      t.string :author
      t.integer :points, null: false, default: 0
      t.integer :num_comments, null: false, default: 0
      t.datetime :posted_at
      t.text :story_text
      t.text :content
      t.string :content_status, null: false, default: "pending"
      t.integer :fetch_attempts, null: false, default: 0
      t.datetime :retry_after
      t.string :fetch_error
      t.json :comments, null: false, default: []
      t.binary :embedding
      t.date :digested_on, index: true
      t.timestamps
    end
    add_index :stories, :hn_id, unique: true
  end
end

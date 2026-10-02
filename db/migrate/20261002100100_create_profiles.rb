class CreateProfiles < ActiveRecord::Migration[8.1]
  def change
    create_table :profiles do |t|
      t.integer :version, null: false
      t.text :description, null: false
      t.json :tag_weights, null: false, default: {}
      t.json :excluded_domains, null: false, default: []
      t.json :excluded_keywords, null: false, default: []
      t.integer :score_threshold, null: false, default: 5
      t.binary :embedding
      t.timestamps
    end
    add_index :profiles, :version, unique: true
  end
end

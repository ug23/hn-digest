class CreateTranslations < ActiveRecord::Migration[8.1]
  def change
    create_table :translations do |t|
      t.references :story, null: false, foreign_key: true, index: { unique: true }
      t.json :segments, null: false, default: []
      t.string :status, null: false, default: "running" # running / done / failed
      t.string :model
      t.string :error
      t.timestamps
    end
  end
end

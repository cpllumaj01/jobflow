class CreateEstimates < ActiveRecord::Migration[8.1]
  def change
    create_table :estimates do |t|
      t.references :job, null: false, foreign_key: true, index: { unique: true }
      t.string :status, null: false, default: "draft"
      t.text :notes
      t.date :expires_on
      t.datetime :approved_at

      t.timestamps
    end
  end
end

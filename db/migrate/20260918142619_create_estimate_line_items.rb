class CreateEstimateLineItems < ActiveRecord::Migration[8.1]
  def change
    create_table :estimate_line_items do |t|
      t.references :estimate, null: false, foreign_key: true
      t.string :description, null: false
      t.decimal :quantity, precision: 10, scale: 2, null: false, default: 1
      t.decimal :unit_price, precision: 12, scale: 2, null: false

      t.timestamps
    end
  end
end

class CreateChangeOrders < ActiveRecord::Migration[8.1]
  def change
    create_table :change_orders do |t|
      t.references :job, null: false, foreign_key: true
      t.string :title, null: false
      t.text :description
      t.string :status, null: false, default: "draft"
      t.datetime :requested_at
      t.datetime :approved_at

      t.timestamps
    end
  end
end

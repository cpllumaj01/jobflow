class CreateJobs < ActiveRecord::Migration[8.1]
  def change
    create_table :jobs do |t|
      t.references :customer, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description
      t.string :address
      t.string :status, null: false, default: "draft"
      t.date :start_date
      t.date :estimated_completion_date
      t.datetime :completed_at

      t.timestamps
    end
  end
end

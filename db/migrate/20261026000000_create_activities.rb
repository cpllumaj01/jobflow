class CreateActivities < ActiveRecord::Migration[8.1]
  def change
    create_table :activities do |t|
      t.references :trackable, polymorphic: true, null: false, index: false
      t.references :actor, foreign_key: { to_table: :users, on_delete: :nullify }
      t.string :event, null: false
      t.jsonb :metadata, null: false, default: {}
      t.datetime :created_at, null: false
    end

    add_index :activities, [ :trackable_type, :trackable_id, :created_at, :id ]
  end
end

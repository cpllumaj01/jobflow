# This file is auto-generated from the current state of the database. Instead
# of editing this file, please use the migrations feature of Active Record to
# incrementally modify your database, and then regenerate this schema definition.
#
# This file is the source Rails uses to define your schema when running `bin/rails
# db:schema:load`. When creating a new database, `bin/rails db:schema:load` tends to
# be faster and is potentially less error prone than running all of your
# migrations from scratch. Old migrations may fail to apply correctly if those
# migrations use external dependencies or application code.
#
# It's strongly recommended that you check this file into your version control system.

ActiveRecord::Schema[8.1].define(version: 2026_09_28_230056) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "active_storage_attachments", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.datetime "created_at", null: false
    t.string "name", null: false
    t.bigint "record_id", null: false
    t.string "record_type", null: false
    t.index ["blob_id"], name: "index_active_storage_attachments_on_blob_id"
    t.index ["record_type", "record_id", "name", "blob_id"], name: "index_active_storage_attachments_uniqueness", unique: true
  end

  create_table "active_storage_blobs", force: :cascade do |t|
    t.bigint "byte_size", null: false
    t.string "checksum"
    t.string "content_type"
    t.datetime "created_at", null: false
    t.string "filename", null: false
    t.string "key", null: false
    t.text "metadata"
    t.string "service_name", null: false
    t.index ["key"], name: "index_active_storage_blobs_on_key", unique: true
  end

  create_table "active_storage_variant_records", force: :cascade do |t|
    t.bigint "blob_id", null: false
    t.string "variation_digest", null: false
    t.index ["blob_id", "variation_digest"], name: "index_active_storage_variant_records_uniqueness", unique: true
  end

  create_table "change_order_line_items", force: :cascade do |t|
    t.bigint "change_order_id", null: false
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.decimal "quantity", precision: 10, scale: 2, default: "1.0", null: false
    t.decimal "unit_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["change_order_id"], name: "index_change_order_line_items_on_change_order_id"
  end

  create_table "change_orders", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.text "description"
    t.bigint "job_id", null: false
    t.datetime "requested_at"
    t.string "status", default: "draft", null: false
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_change_orders_on_job_id"
  end

  create_table "customers", force: :cascade do |t|
    t.string "address"
    t.string "contact_name"
    t.datetime "created_at", null: false
    t.string "email"
    t.string "name", null: false
    t.text "notes"
    t.string "phone"
    t.datetime "updated_at", null: false
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_customers_on_user_id"
  end

  create_table "estimate_line_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "description", null: false
    t.bigint "estimate_id", null: false
    t.decimal "quantity", precision: 10, scale: 2, default: "1.0", null: false
    t.decimal "unit_price", precision: 12, scale: 2, null: false
    t.datetime "updated_at", null: false
    t.index ["estimate_id"], name: "index_estimate_line_items_on_estimate_id"
  end

  create_table "estimates", force: :cascade do |t|
    t.datetime "approved_at"
    t.datetime "created_at", null: false
    t.date "expires_on"
    t.bigint "job_id", null: false
    t.text "notes"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["job_id"], name: "index_estimates_on_job_id", unique: true
  end

  create_table "jobs", force: :cascade do |t|
    t.string "address"
    t.datetime "completed_at"
    t.datetime "created_at", null: false
    t.bigint "customer_id", null: false
    t.text "description"
    t.date "estimated_completion_date"
    t.string "name", null: false
    t.date "start_date"
    t.string "status", default: "draft", null: false
    t.datetime "updated_at", null: false
    t.index ["customer_id"], name: "index_jobs_on_customer_id"
  end

  create_table "sessions", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "ip_address"
    t.datetime "updated_at", null: false
    t.string "user_agent"
    t.bigint "user_id", null: false
    t.index ["user_id"], name: "index_sessions_on_user_id"
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "email_address", null: false
    t.string "password_digest", null: false
    t.datetime "updated_at", null: false
    t.index ["email_address"], name: "index_users_on_email_address", unique: true
  end

  add_foreign_key "active_storage_attachments", "active_storage_blobs", column: "blob_id"
  add_foreign_key "active_storage_variant_records", "active_storage_blobs", column: "blob_id"
  add_foreign_key "change_order_line_items", "change_orders"
  add_foreign_key "change_orders", "jobs"
  add_foreign_key "customers", "users"
  add_foreign_key "estimate_line_items", "estimates"
  add_foreign_key "estimates", "jobs"
  add_foreign_key "jobs", "customers"
  add_foreign_key "sessions", "users"
end

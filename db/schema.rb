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

ActiveRecord::Schema[8.1].define(version: 2026_07_21_105232) do
  # These are extensions that must be enabled in order to support this database
  enable_extension "pg_catalog.plpgsql"

  create_table "player_states", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "current_queue_item_id"
    t.integer "duration_ms", default: 0, null: false
    t.integer "position_ms", default: 0, null: false
    t.string "status", default: "stopped", null: false
    t.datetime "updated_at", null: false
    t.integer "volume", default: 80, null: false
  end

  create_table "queue_items", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.bigint "position", null: false
    t.string "queued_by", null: false
    t.string "state", default: "queued", null: false
    t.bigint "track_id", null: false
    t.datetime "updated_at", null: false
    t.index ["position"], name: "index_queue_items_on_position"
    t.index ["state"], name: "index_queue_items_on_state"
    t.index ["track_id"], name: "index_queue_items_on_track_id"
  end

  create_table "skip_votes", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.string "nick", null: false
    t.bigint "queue_item_id", null: false
    t.datetime "updated_at", null: false
    t.index ["queue_item_id", "nick"], name: "index_skip_votes_on_queue_item_id_and_nick", unique: true
    t.index ["queue_item_id"], name: "index_skip_votes_on_queue_item_id"
  end

  create_table "tracks", force: :cascade do |t|
    t.string "album"
    t.string "artist"
    t.integer "cache_attempts", default: 0, null: false
    t.string "cache_path"
    t.string "cache_status", default: "none", null: false
    t.datetime "created_at", null: false
    t.integer "duration_ms"
    t.datetime "file_mtime"
    t.text "last_error"
    t.string "local_path"
    t.virtual "search_vector", type: :tsvector, as: "to_tsvector('simple'::regconfig, (((((COALESCE(title, ''::character varying))::text || ' '::text) || (COALESCE(artist, ''::character varying))::text) || ' '::text) || (COALESCE(album, ''::character varying))::text))", stored: true
    t.string "source", null: false
    t.string "source_uid", null: false
    t.string "thumbnail_url"
    t.string "title", null: false
    t.datetime "updated_at", null: false
    t.index ["cache_status"], name: "index_tracks_on_cache_status"
    t.index ["search_vector"], name: "index_tracks_on_search_vector", using: :gin
    t.index ["source", "source_uid"], name: "index_tracks_on_source_and_source_uid", unique: true
  end

  create_table "users", force: :cascade do |t|
    t.datetime "created_at", null: false
    t.datetime "last_seen_at"
    t.datetime "moved_at"
    t.string "nick", null: false
    t.datetime "updated_at", null: false
    t.index ["nick"], name: "index_users_on_nick", unique: true
  end

  add_foreign_key "queue_items", "tracks"
  add_foreign_key "skip_votes", "queue_items"
end

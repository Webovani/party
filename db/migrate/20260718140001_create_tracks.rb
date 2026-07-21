class CreateTracks < ActiveRecord::Migration[8.1]
  def change
    create_table :tracks do |t|
      t.string  :source, null: false                 # "local" | "youtube"
      t.string  :source_uid, null: false             # local relative path | youtube videoId
      t.string  :title, null: false
      t.string  :artist
      t.string  :album
      t.integer :duration_ms
      t.string  :thumbnail_url
      t.string  :local_path                           # absolute path for local files
      t.string  :cache_status, null: false, default: "none" # none|pending|ready|error (youtube)
      t.string  :cache_path                           # downloaded audio file (youtube)
      t.text    :last_error

      # Full-text search vector, maintained by PostgreSQL. "simple" config avoids
      # English-only stemming (library may hold many languages).
      t.virtual :search_vector, type: :tsvector, stored: true, as: <<~SQL.squish
        to_tsvector('simple',
          coalesce(title, '') || ' ' || coalesce(artist, '') || ' ' || coalesce(album, ''))
      SQL

      t.timestamps
    end

    add_index :tracks, %i[source source_uid], unique: true
    add_index :tracks, :search_vector, using: :gin
    add_index :tracks, :cache_status
  end
end

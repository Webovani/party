class AddTrigramSearchToTracks < ActiveRecord::Migration[8.1]
  def change
    enable_extension "pg_trgm"

    # Same three fields the tsvector is built from, kept as plain text so trigram
    # similarity can run against it. Stored/generated, so it can't drift.
    add_column :tracks, :search_text, :virtual, type: :text, stored: true,
      as: "coalesce(title, '') || ' ' || coalesce(artist, '') || ' ' || coalesce(album, '')"

    add_index :tracks, :search_text, using: :gin, opclass: :gin_trgm_ops,
      name: "index_tracks_on_search_text_trgm"
  end
end

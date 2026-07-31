class UnaccentSearch < ActiveRecord::Migration[8.1]
  # Diacritics must not affect search at all: a Czech library gets typed without
  # them constantly ("cechomor" for "Čechomor"). Handling that at index time makes
  # it an exact, fast FTS hit rather than something the fuzzy fallback rescues.
  #
  # unaccent() is STABLE, not IMMUTABLE, so it cannot be used in a generated column
  # or an index expression. The two-argument form with an explicit regdictionary
  # does not depend on search_path, which is what makes this wrapper safe to mark
  # IMMUTABLE (the standard PostgreSQL recipe).
  FUNCTION = <<~SQL.freeze
    CREATE OR REPLACE FUNCTION party_unaccent(text) RETURNS text
      LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
    $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$;
  SQL

  TEXT = "coalesce(title, '') || ' ' || coalesce(artist, '') || ' ' || coalesce(album, '')".freeze

  def up
    enable_extension "unaccent"
    execute FUNCTION

    remove_index :tracks, :search_vector
    remove_column :tracks, :search_vector
    add_column :tracks, :search_vector, :virtual, type: :tsvector, stored: true,
      as: "to_tsvector('simple', party_unaccent(#{TEXT}))"
    add_index :tracks, :search_vector, using: :gin

    remove_index :tracks, name: "index_tracks_on_search_text_trgm"
    remove_column :tracks, :search_text
    add_column :tracks, :search_text, :virtual, type: :text, stored: true,
      as: "party_unaccent(#{TEXT})"
    add_index :tracks, :search_text, using: :gin, opclass: :gin_trgm_ops,
      name: "index_tracks_on_search_text_trgm"
  end

  def down
    remove_index :tracks, :search_vector
    remove_column :tracks, :search_vector
    add_column :tracks, :search_vector, :virtual, type: :tsvector, stored: true,
      as: "to_tsvector('simple', #{TEXT})"
    add_index :tracks, :search_vector, using: :gin

    remove_index :tracks, name: "index_tracks_on_search_text_trgm"
    remove_column :tracks, :search_text
    add_column :tracks, :search_text, :virtual, type: :text, stored: true, as: TEXT
    add_index :tracks, :search_text, using: :gin, opclass: :gin_trgm_ops,
      name: "index_tracks_on_search_text_trgm"

    execute "DROP FUNCTION IF EXISTS party_unaccent(text);"
  end
end

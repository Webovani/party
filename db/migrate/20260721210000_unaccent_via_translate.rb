class UnaccentViaTranslate < ActiveRecord::Migration[8.1]
  # Diacritics must not affect search at all, so they are stripped at INDEX time:
  # "cechomor" is then an exact FTS hit on "Čechomor", not a fuzzy rescue.
  #
  # translate() rather than unaccent(). unaccent() is STABLE and so cannot be used
  # in a generated column, and the usual IMMUTABLE wrapper function CANNOT be
  # represented in schema.rb — the columns reference it, so every fresh
  # db:schema:load (db:test:prepare, a new machine) died with "function does not
  # exist". translate() is IMMUTABLE and built in, so schema.rb stays sufficient.
  #
  # 177 letters (Latin-1 Supplement + Latin Extended-A), generated from
  # ActiveSupport transliteration. Track::UNACCENT_FROM/TO must stay byte-identical
  # or queries stop matching what the index stores.
  FROM = "ÀÁÂÃÄÅÇÈÉÊËÌÍÎÏÐÑÒÓÔÕÖØÙÚÛÜÝàáâãäåçèéêëìíîïðñòóôõöøùúûüýÿĀāĂăĄąĆćĈĉĊċČčĎďĐđĒēĔĕĖėĘęĚěĜĝĞğĠġĢģĤĥĦħĨĩĪīĬĭĮįİıĴĵĶķĸĹĺĻļĽľĿŀŁłŃńŅņŇňŌōŎŏŐőŔŕŖŗŘřŚśŜŝŞşŠšŢţŤťŦŧŨũŪūŬŭŮůŰűŲųŴŵŶŷŸŹźŻżŽž".freeze
  TO   = "AAAAAACEEEEIIIIDNOOOOOOUUUUYaaaaaaceeeeiiiidnoooooouuuuyyAaAaAaCcCcCcCcDdDdEeEeEeEeEeGgGgGgGgHhHhIiIiIiIiIiJjKkkLlLlLlLlLlNnNnNnOoOoOoRrRrRrSsSsSsSsTtTtTtUuUuUuUuUuUuWwYyYZzZzZz".freeze
  TEXT = "coalesce(title, '') || ' ' || coalesce(artist, '') || ' ' || coalesce(album, '')".freeze

  def up
    rebuild("translate(#{TEXT}, #{connection.quote(FROM)}, #{connection.quote(TO)})")
    execute "DROP FUNCTION IF EXISTS party_unaccent(text);"
    disable_extension "unaccent"
  end

  def down
    enable_extension "unaccent"
    execute <<~SQL
      CREATE OR REPLACE FUNCTION party_unaccent(text) RETURNS text
        LANGUAGE sql IMMUTABLE STRICT PARALLEL SAFE AS
      $$ SELECT public.unaccent('public.unaccent'::regdictionary, $1) $$;
    SQL
    rebuild("party_unaccent(#{TEXT})")
  end

  private

  def rebuild(normalized)
    remove_index :tracks, :search_vector
    remove_column :tracks, :search_vector
    add_column :tracks, :search_vector, :virtual, type: :tsvector, stored: true,
      as: "to_tsvector('simple', #{normalized})"
    add_index :tracks, :search_vector, using: :gin

    remove_index :tracks, name: "index_tracks_on_search_text_trgm"
    remove_column :tracks, :search_text
    add_column :tracks, :search_text, :virtual, type: :text, stored: true, as: normalized
    add_index :tracks, :search_text, using: :gin, opclass: :gin_trgm_ops,
      name: "index_tracks_on_search_text_trgm"
  end
end

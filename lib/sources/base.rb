module Sources
  # Interface every music source implements. A source turns a text query into a
  # list of normalized result hashes:
  #
  #   { source:, source_uid:, title:, artist:, duration_ms:, thumbnail_url:, ... }
  #
  # Kept free of controller/view concerns so the whole `Sources` tree could later
  # be extracted into a standalone gem.
  class Base
    # Stable identifier, e.g. "local", "youtube". Derived from the class name.
    def self.source_name
      name.demodulize.underscore
    end

    def source_name
      self.class.source_name
    end

    # @param query [String]
    # @param limit [Integer]
    # @return [Array<Hash>] normalized results
    def search(query, limit: 25)
      raise NotImplementedError, "#{self.class} must implement #search"
    end
  end
end

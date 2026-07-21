module Sources
  # Central list of active sources. Adding a source = add one line here.
  module Registry
    module_function

    def all
      @all ||= [Sources::Local.new, Sources::Youtube.new]
    end

    # Reset memoized sources (used in tests).
    def reset!
      @all = nil
    end

    def find(source_name)
      all.find { |s| s.source_name == source_name.to_s }
    end

    # Search every source. Returns an ordered array of
    # { source: "local", results: [...] }, one entry per source.
    # A failure in one source (e.g. YouTube unreachable) never breaks the others.
    def search_all(query, limit: 25)
      all.map do |source|
        { source: source.source_name, results: safe_search(source, query, limit) }
      end
    end

    def safe_search(source, query, limit)
      source.search(query, limit: limit)
    rescue => e
      Rails.logger.error("[Sources] #{source.source_name} search failed: #{e.class}: #{e.message}")
      []
    end
  end
end

module Sources
  # Central list of active sources. Adding a source = add one line here.
  module Registry
    module_function

    # Local drops out entirely when no music_dir is configured, so an unscoped
    # search simply never asks it — no empty "Local library" section, no results
    # pointing at files this deployment cannot browse.
    def all
      @all ||= [(Sources::Local.new if PartyConfig.local_library?), Sources::Youtube.new].compact
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

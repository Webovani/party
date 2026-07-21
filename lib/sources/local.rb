module Sources
  # Searches the indexed local library (Track rows with source "local") using
  # PostgreSQL full-text search.
  class Local < Base
    # `scope` optionally narrows the search to a subset of the local library
    # (an artist/album/folder relation); defaults to the whole library.
    def search(query, limit: 25, scope: nil)
      (scope || Track.local).search(query).limit(limit).map(&:to_search_result)
    end
  end
end

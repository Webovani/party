require "net/http"
require "json"

module Sources
  # YouTube search via the InnerTube "youtubei/v1/search" endpoint (see
  # InnertubeClient). No API key or Python required. Also resolves a pasted
  # YouTube URL to a single result.
  class Youtube < Base
    ID_RE = /\A[A-Za-z0-9_-]{11}\z/

    def search(query, limit: 25)
      InnertubeClient.new.search(query, limit: limit)
    end

    # If `query` is a YouTube URL/short-link, return a single normalized result
    # for that video; otherwise nil. Metadata comes from YouTube's oEmbed endpoint
    # (title + channel); a failure still yields a queueable result with a fallback
    # title, since the id is all caching actually needs.
    def resolve_url(query)
      id = self.class.extract_video_id(query)
      return nil unless id

      meta = fetch_oembed(id)
      {
        source: "youtube",
        source_uid: id,
        title: meta[:title].presence || "YouTube video (#{id})",
        artist: meta[:author],
        duration_ms: nil,
        thumbnail_url: "https://i.ytimg.com/vi/#{id}/hqdefault.jpg"
      }
    end

    # Pull an 11-char video id out of a YouTube URL (watch, youtu.be, shorts,
    # embed, live, music/m subdomains). Returns nil for anything else — including
    # bare ids, to avoid mistaking a normal search term for an id.
    def self.extract_video_id(query)
      q = query.to_s.strip
      return nil unless q.match?(%r{\Ahttps?://}i)

      uri = URI.parse(q) rescue (return nil)
      return nil unless uri.host

      host = uri.host.downcase.sub(/\Awww\./, "")
      id =
        case host
        when "youtu.be"
          uri.path.delete_prefix("/").split("/").first
        when "youtube.com", "m.youtube.com", "music.youtube.com", "gaming.youtube.com"
          if uri.path == "/watch"
            URI.decode_www_form(uri.query.to_s).to_h["v"]
          elsif uri.path.match?(%r{\A/(shorts|embed|v|live)/})
            uri.path.split("/")[2]
          end
        end

      id if id.to_s.match?(ID_RE)
    end

    private

    def fetch_oembed(id)
      uri = URI("https://www.youtube.com/oembed")
      uri.query = URI.encode_www_form(url: "https://www.youtube.com/watch?v=#{id}", format: "json")

      http = Net::HTTP.new(uri.host, uri.port)
      http.use_ssl = true
      http.open_timeout = 5
      http.read_timeout = 8
      res = http.get(uri.request_uri)
      return {} unless res.is_a?(Net::HTTPSuccess)

      json = JSON.parse(res.body)
      { title: json["title"], author: json["author_name"] }
    rescue => e
      Rails.logger.warn("[Sources::Youtube] oembed failed for #{id}: #{e.class}: #{e.message}")
      {}
    end
  end
end

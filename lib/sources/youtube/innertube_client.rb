require "net/http"
require "json"

module Sources
  class Youtube
    # Reimplements the mopidy_youtube "jAPI" search hack in pure Ruby: a POST to
    # YouTube's private InnerTube endpoint with a spoofed WEB client and the
    # well-known public InnerTube key. Returns normalized result hashes.
    #
    # If YouTube ever rotates the key or client version, bump the constants here.
    class InnertubeClient
      ENDPOINT       = "https://www.youtube.com/youtubei/v1/search".freeze
      API_KEY        = "AIzaSyAO_FJ2SlqU8Q4STEHLGCilw_Y9_11qcW8".freeze
      CLIENT_NAME    = "WEB".freeze
      CLIENT_VERSION = "2.20200720.00.02".freeze
      VIDEOS_PARAMS  = "EgIQAQ==".freeze # search filter token: videos only
      USER_AGENT     = "Mozilla/5.0".freeze
      SKIP_TITLES    = ["[Private video]", "[Deleted video]"].freeze

      OPEN_TIMEOUT = 6
      READ_TIMEOUT = 15

      class Error < StandardError; end

      def search(query, limit: 25)
        query = query.to_s.strip
        return [] if query.empty?

        json = post_search(query)
        parse(json).first(limit)
      end

      private

      def post_search(query)
        uri = URI(ENDPOINT)
        uri.query = URI.encode_www_form(
          "query"          => query,
          "key"            => API_KEY,
          "params"         => VIDEOS_PARAMS,
          "contentCheckOk" => "true",
          "racyCheckOk"    => "true"
        )

        request = Net::HTTP::Post.new(uri)
        request["User-Agent"]      = USER_AGENT
        request["accept-language"] = "en-US,en"
        request["Content-Type"]    = "application/json"
        # Consent/pref cookies dodge the EU consent interstitial (from mopidy).
        request["Cookie"]          = "PREF=hl=en; CONSENT=YES+20210329;"
        request.body = JSON.generate(
          context: { client: { clientName: CLIENT_NAME, clientVersion: CLIENT_VERSION } }
        )

        response = http(uri).request(request)
        unless response.is_a?(Net::HTTPSuccess)
          raise Error, "InnerTube search HTTP #{response.code}"
        end

        JSON.parse(response.body)
      rescue JSON::ParserError => e
        raise Error, "InnerTube response was not JSON: #{e.message}"
      end

      def http(uri)
        Net::HTTP.new(uri.host, uri.port).tap do |h|
          h.use_ssl = uri.scheme == "https"
          h.open_timeout = OPEN_TIMEOUT
          h.read_timeout = READ_TIMEOUT
        end
      end

      def parse(json)
        sections = json.dig(
          "contents", "twoColumnSearchResultsRenderer", "primaryContents",
          "sectionListRenderer", "contents"
        ) || []

        sections
          .flat_map { |section| section.dig("itemSectionRenderer", "contents") || [] }
          .filter_map { |item| video_to_result(item["videoRenderer"]) }
      end

      def video_to_result(video)
        return nil unless video

        video_id = video["videoId"]
        return nil if video_id.nil? || video_id.empty?

        title = video.dig("title", "simpleText") || video.dig("title", "runs", 0, "text")
        return nil if title.nil? || title.empty? || SKIP_TITLES.include?(title)

        byline = video["longBylineText"] || video["shortBylineText"]

        {
          source:        "youtube",
          source_uid:    video_id,
          title:         title,
          artist:        byline&.dig("runs", 0, "text"),
          duration_ms:   parse_length(video.dig("lengthText", "simpleText")),
          thumbnail_url: best_thumbnail(video)
        }
      end

      # "3:45" -> 225000, "1:02:03" -> 3723000, nil/live -> nil
      def parse_length(text)
        return nil if text.nil? || text.empty?

        parts = text.split(":")
        return nil unless parts.all? { |p| p.match?(/\A\d+\z/) }

        seconds = parts.map(&:to_i).reduce(0) { |acc, p| acc * 60 + p }
        seconds * 1000
      end

      def best_thumbnail(video)
        url = video.dig("thumbnail", "thumbnails")&.last&.fetch("url", nil)
        url && url.split("?").first
      end
    end
  end
end

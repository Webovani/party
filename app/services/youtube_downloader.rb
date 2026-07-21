require "open3"

# Downloads YouTube audio to the cache directory via yt-dlp. Pure audio, no
# re-encode (mpv plays m4a/opus/webm), named "<videoId>.<ext>".
class YoutubeDownloader
  class Error < StandardError; end

  FORMAT = "bestaudio/ogg/mp3/m4a/best".freeze

  def initialize(cache_dir: PartyConfig[:cache_dir])
    @cache_dir = Pathname.new(cache_dir.to_s)
  end

  # Returns the absolute path to the cached audio file.
  def download(video_id)
    @cache_dir.mkpath
    url = "https://www.youtube.com/watch?v=#{video_id}"
    cmd = [
      "yt-dlp",
      "-f", FORMAT,
      "-o", @cache_dir.join("%(id)s.%(ext)s").to_s,
      # Try the default player clients, falling back to the Android client, which
      # serves some videos the web client refuses ("not available on this app").
      "--extractor-args", "youtube:player_client=default,android",
      "--no-playlist", "--no-progress", "--no-warnings",
      "--no-part", "--retries", "5",
      url
    ]

    _out, err, status = Open3.capture3(*cmd)
    unless status.success?
      detail = err.to_s.lines.last(3).join.strip
      raise Error, detail.presence || "yt-dlp exited #{status.exitstatus}"
    end

    file = cached_file(video_id)
    raise Error, "yt-dlp finished but produced no file for #{video_id}" unless file

    file.to_s
  end

  # Existing cached file for this id, or nil.
  def cached_file(video_id)
    Dir.glob(@cache_dir.join("#{video_id}.*"))
       .reject { |f| f.end_with?(".part") }
       .map { |f| Pathname.new(f) }
       .find(&:file?)
  end
end

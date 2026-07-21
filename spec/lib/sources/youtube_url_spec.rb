require "rails_helper"

RSpec.describe Sources::Youtube do
  describe ".extract_video_id" do
    it "parses the common URL shapes" do
      {
        "https://www.youtube.com/watch?v=dQw4w9WgXcQ"            => "dQw4w9WgXcQ",
        "http://youtube.com/watch?v=dQw4w9WgXcQ&list=xyz&t=42"   => "dQw4w9WgXcQ",
        "https://youtu.be/dQw4w9WgXcQ?si=abc"                     => "dQw4w9WgXcQ",
        "https://m.youtube.com/watch?v=dQw4w9WgXcQ"              => "dQw4w9WgXcQ",
        "https://music.youtube.com/watch?v=dQw4w9WgXcQ"          => "dQw4w9WgXcQ",
        "https://www.youtube.com/shorts/dQw4w9WgXcQ"             => "dQw4w9WgXcQ",
        "https://www.youtube.com/embed/dQw4w9WgXcQ"              => "dQw4w9WgXcQ",
        "https://www.youtube.com/live/dQw4w9WgXcQ"               => "dQw4w9WgXcQ"
      }.each do |url, id|
        expect(described_class.extract_video_id(url)).to eq(id), "for #{url}"
      end
    end

    it "returns nil for non-URLs and non-YouTube URLs" do
      ["daft punk", "dQw4w9WgXcQ", "", "https://example.com/watch?v=dQw4w9WgXcQ",
       "https://www.youtube.com/results?search_query=x"].each do |q|
        expect(described_class.extract_video_id(q)).to be_nil, "for #{q.inspect}"
      end
    end
  end

  describe "#resolve_url" do
    def stub_oembed(status: 200, body: { title: "Never Gonna Give You Up", author_name: "Rick Astley" }.to_json)
      stub_request(:get, /youtube\.com\/oembed/).to_return(status: status, body: body,
                                                           headers: { "Content-Type" => "application/json" })
    end

    it "returns a normalized result with oEmbed metadata" do
      stub_oembed
      result = described_class.new.resolve_url("https://youtu.be/dQw4w9WgXcQ")
      expect(result).to include(
        source: "youtube",
        source_uid: "dQw4w9WgXcQ",
        title: "Never Gonna Give You Up",
        artist: "Rick Astley",
        thumbnail_url: "https://i.ytimg.com/vi/dQw4w9WgXcQ/hqdefault.jpg"
      )
    end

    it "still returns a queueable result when oEmbed fails" do
      stub_oembed(status: 404, body: "nope")
      result = described_class.new.resolve_url("https://www.youtube.com/watch?v=dQw4w9WgXcQ")
      expect(result).to include(source_uid: "dQw4w9WgXcQ", title: "YouTube video (dQw4w9WgXcQ)")
    end

    it "returns nil for a normal search query (no network)" do
      expect(described_class.new.resolve_url("daft punk")).to be_nil
      expect(a_request(:get, /oembed/)).not_to have_been_made
    end
  end
end

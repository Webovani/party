require "rails_helper"

RSpec.describe Sources::Youtube::InnertubeClient do
  subject(:client) { described_class.new }

  let(:fixture) { Rails.root.join("spec/fixtures/innertube_search.json").read }

  def stub_search(body: fixture, status: 200)
    stub_request(:post, /youtube\.com\/youtubei\/v1\/search/)
      .to_return(status: status, body: body, headers: { "Content-Type" => "application/json" })
  end

  describe "#search" do
    it "posts to the InnerTube endpoint with the spoofed WEB client and public key" do
      stub = stub_search
      client.search("daft punk")

      expect(stub).to have_been_requested
      expect(a_request(:post, /youtubei\/v1\/search/).with { |req|
        uri = URI(req.uri)
        params = URI.decode_www_form(uri.query).to_h
        body = JSON.parse(req.body)
        params["key"] == described_class::API_KEY &&
          params["params"] == described_class::VIDEOS_PARAMS &&
          params["query"] == "daft punk" &&
          body.dig("context", "client", "clientName") == "WEB" &&
          req.headers["User-Agent"] == "Mozilla/5.0"
      }).to have_been_made
    end

    it "normalizes video results and extracts metadata" do
      stub_search
      results = client.search("daft punk")

      first = results.first
      expect(first).to include(
        source: "youtube",
        source_uid: "K4DyBUG242c",
        title: "Daft Punk - Around the World (Official Video)",
        artist: "Daft Punk",
        duration_ms: (7 * 60 + 8) * 1000
      )
      # thumbnail query string is stripped
      expect(first[:thumbnail_url]).to eq("https://i.ytimg.com/vi/K4DyBUG242c/hq.jpg")
    end

    it "reads title from simpleText and byline from shortBylineText" do
      stub_search
      second = client.search("daft punk")[1]

      expect(second).to include(
        source_uid: "s9MszVE7aR4",
        title: "Daft Punk - Harder Better Faster Stronger",
        artist: "DaftPunkVEVO",
        duration_ms: (3 * 60 + 45) * 1000
      )
    end

    it "skips private/deleted videos and non-video renderers" do
      stub_search
      ids = client.search("daft punk").map { |r| r[:source_uid] }

      expect(ids).to eq(%w[K4DyBUG242c s9MszVE7aR4])
    end

    it "honors the limit" do
      stub_search
      expect(client.search("daft punk", limit: 1).size).to eq(1)
    end

    it "returns [] for a blank query without hitting the network" do
      expect(client.search("   ")).to eq([])
      expect(a_request(:post, /youtubei/)).not_to have_been_made
    end

    it "raises a wrapped error on non-2xx responses" do
      stub_search(status: 500, body: "nope")
      expect { client.search("x") }.to raise_error(described_class::Error, /HTTP 500/)
    end

    it "raises a wrapped error on non-JSON responses" do
      stub_search(body: "<html>not json</html>")
      expect { client.search("x") }.to raise_error(described_class::Error, /not JSON/)
    end
  end
end

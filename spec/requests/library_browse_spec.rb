require "rails_helper"

RSpec.describe "Library browsing", type: :request do
  let(:music_dir) { PartyConfig[:music_dir] }

  def local_track(artist:, album:, title:, rel:)
    create(:track, :local, artist: artist, album: album, title: title,
                           source_uid: File.join(music_dir, rel),
                           local_path: File.join(music_dir, rel))
  end

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    post session_path, params: { nick: "dj" }

    local_track(artist: "ABBA", album: "Gold", title: "SOS",           rel: "ABBA/Gold/sos.mp3")
    local_track(artist: "ABBA", album: "Gold", title: "Mamma Mia",     rel: "ABBA/Gold/mamma.mp3")
    local_track(artist: "ABBA", album: "Waterloo", title: "Waterloo",  rel: "ABBA/Waterloo/waterloo.mp3")
    local_track(artist: "Queen", album: "News", title: "We Will Rock", rel: "Queen/News/rock.mp3")
  end

  describe "artist / album browsing" do
    it "lists artists" do
      get library_path, headers: { "Turbo-Frame" => "search_results" }
      expect(response.body).to include("ABBA", "Queen")
    end

    it "lists an artist's albums" do
      get library_path(browse: "artists", artist: "ABBA"), headers: { "Turbo-Frame" => "search_results" }
      expect(response.body).to include("Gold", "Waterloo")
    end

    it "lists an album's tracks" do
      get library_path(browse: "artists", artist: "ABBA", album: "Gold"),
          headers: { "Turbo-Frame" => "search_results" }
      expect(response.body).to include("SOS", "Mamma Mia")
      expect(response.body).not_to include("Waterloo")
    end
  end

  describe "folder browsing" do
    it "lists top-level folders" do
      get library_path(browse: "folders"), headers: { "Turbo-Frame" => "search_results" }
      expect(response.body).to include("ABBA", "Queen")
    end

    it "drills into a folder showing subfolders" do
      get library_path(browse: "folders", path: "ABBA"), headers: { "Turbo-Frame" => "search_results" }
      expect(response.body).to include("Gold", "Waterloo")
    end
  end

  describe "bulk add" do
    it "adds a whole album" do
      expect {
        post add_album_queue_items_path, params: { artist: "ABBA", album: "Gold" }
      }.to change(QueueItem, :count).by(2)
    end

    it "adds a whole folder recursively" do
      expect {
        post add_folder_queue_items_path, params: { path: "ABBA" }
      }.to change(QueueItem, :count).by(3) # Gold(2) + Waterloo(1)
    end

    it "respects the per-user limit and reports skips" do
      allow(Rails.application.config).to receive(:party)
        .and_return(Rails.application.config.party.merge(max_queue_per_user: 1))
      post add_folder_queue_items_path, params: { path: "ABBA" }
      expect(QueueItem.count).to eq(1)
      expect(response.body).to include("skipped")
    end
  end

  describe "prefix search" do
    it "matches on a word prefix" do
      results = Sources::Local.new.search("wate")
      expect(results.map { |r| r[:title] }).to include("Waterloo")
    end

    it "ANDs multiple prefixes" do
      results = Sources::Local.new.search("abb gol")
      titles = results.map { |r| r[:title] }
      expect(titles).to include("SOS", "Mamma Mia")
      expect(titles).not_to include("We Will Rock")
    end
  end
end

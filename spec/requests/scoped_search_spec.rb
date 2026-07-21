require "rails_helper"

RSpec.describe "Scoped search", type: :request do
  let(:music_dir) { PartyConfig[:music_dir] }

  def local_track(artist:, album:, title:, rel:)
    create(:track, :local, artist: artist, album: album, title: title,
                           source_uid: File.join(music_dir, rel),
                           local_path: File.join(music_dir, rel))
  end

  def search(params)
    get search_path(params), headers: { "Turbo-Frame" => "search_results" }
  end

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    post session_path, params: { nick: "dj" }

    local_track(artist: "ABBA",  album: "Gold",     title: "Waterloo Sunset", rel: "ABBA/Gold/ws.mp3")
    local_track(artist: "ABBA",  album: "Waterloo", title: "Honey Honey",     rel: "ABBA/Waterloo/hh.mp3")
    local_track(artist: "Queen", album: "News",     title: "Waterworld",      rel: "Queen/News/ww.mp3")
    Sources::Registry.reset!
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([
      { source: "youtube", source_uid: "yt1", title: "Waterloo (YouTube)", artist: "x", duration_ms: 1 }
    ])
  end

  after { Sources::Registry.reset! }

  it "searches globally (local + YouTube) when unscoped" do
    search(q: "water")
    expect(response.body).to include("Waterloo Sunset", "Waterworld", "Waterloo (YouTube)")
  end

  it "restricts results to the artist scope and omits YouTube" do
    search(q: "water", browse: "artists", artist: "ABBA")
    expect(response.body).to include("Waterloo Sunset")   # ABBA
    expect(response.body).not_to include("Waterworld")    # Queen — out of scope
    expect(response.body).not_to include("Waterloo (YouTube)")
  end

  it "restricts results to an album scope" do
    search(q: "honey", browse: "artists", artist: "ABBA", album: "Waterloo")
    expect(response.body).to include("Honey Honey")
    # a term only present in the other album returns nothing here
    search(q: "sunset", browse: "artists", artist: "ABBA", album: "Waterloo")
    expect(response.body).not_to include("Waterloo Sunset")
  end

  it "restricts results to a folder scope" do
    search(q: "water", browse: "folders", path: "Queen")
    expect(response.body).to include("Waterworld")
    expect(response.body).not_to include("Waterloo Sunset")
  end

  it "returns to the browse view when the query is cleared while scoped" do
    search(q: "", browse: "artists", artist: "ABBA")
    expect(response).to redirect_to(library_path(browse: "artists", artist: "ABBA"))
  end
end

require "rails_helper"

# YouTube-only deployment: config/party.yml's music_dir is blank, so there is no
# local library to browse, search, or add from. Everything below is about that
# one switch (PartyConfig.local_library?) reaching every surface.
RSpec.describe "Without a local library", type: :request do
  # Rows from before the library was switched off (or from a drive that used to
  # be mounted) stay in the DB — the point is that they stop being reachable.
  let!(:leftover) do
    create(:track, :local, artist: "ABBA", album: "Gold", title: "Waterloo Sunset",
                           source_uid: "/gone/ABBA/Gold/ws.mp3", local_path: "/gone/ABBA/Gold/ws.mp3")
  end

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    allow(PartyConfig).to receive(:music_dir).and_return(nil)
    # Registry memoizes its source list, so it has to be rebuilt around the stub.
    Sources::Registry.reset!
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([
      { source: "youtube", source_uid: "yt1", title: "Waterloo (YouTube)", artist: "x", duration_ms: 1 }
    ])
    post session_path, params: { nick: "dj" }
  end

  after { Sources::Registry.reset! }

  it "drops the Library tab" do
    get root_path
    expect(response.body).to include("History")
    expect(response.body).not_to include(">Library<")
  end

  it "sends a stale /library link back home" do
    get library_path(browse: "artists")
    expect(response).to redirect_to(root_path)
  end

  it "searches YouTube only" do
    get search_path(q: "water"), headers: { "Turbo-Frame" => "search_results" }
    expect(response.body).to include("Waterloo (YouTube)")
    expect(response.body).not_to include("Waterloo Sunset")
    expect(response.body).not_to include("Local library")
  end

  it "ignores a bookmarked browse scope instead of scoping to a library that isn't there" do
    get search_path(q: "water", browse: "albums"), headers: { "Turbo-Frame" => "search_results" }
    expect(response).to have_http_status(:ok)
    expect(response.body).to include("Waterloo (YouTube)")  # fell back to a plain search
    expect(response.body).not_to include("Waterloo Sunset")
  end

  it "refuses to queue a local track" do
    expect {
      post queue_items_path, params: { source: "local", source_uid: leftover.local_path,
                                       title: leftover.title, local_path: leftover.local_path }
    }.not_to change(QueueItem, :count)
    expect(response.body).to include("YouTube only")
  end

  it "still queues a YouTube track" do
    expect {
      post queue_items_path, params: { source: "youtube", source_uid: "yt1", title: "Waterloo (YouTube)" }
    }.to change(QueueItem, :count).by(1)
  end

  it "hides played local tracks from history" do
    create(:queue_item, track: leftover, state: "played", queued_by: "dj")
    get history_path, headers: { "Turbo-Frame" => "search_results" }
    expect(response.body).not_to include("Waterloo Sunset")
  end

  it "scans nothing, and prunes nothing" do
    result = LibraryScanner.new.call
    expect(result.skipped).to be(true)
    expect(result.reason).to eq(:disabled)
    expect { result }.not_to change(Track, :count)
  end

  it "keeps LocalLibrary from treating the working directory as the library" do
    expect { LocalLibrary.new.music_dir }.to raise_error(LocalLibrary::Disabled)
  end
end

RSpec.describe "With a local library configured", type: :request do
  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    post session_path, params: { nick: "dj" }
  end

  it "still offers the Library tab" do
    get root_path
    expect(response.body).to include(">Library<")
  end

  it "still browses" do
    get library_path(browse: "artists"), headers: { "Turbo-Frame" => "search_results" }
    expect(response).to have_http_status(:ok)
  end
end

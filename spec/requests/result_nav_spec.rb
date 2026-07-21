require "rails_helper"

RSpec.describe "Result navigation to album/folder", type: :request do
  let(:music_dir) { PartyConfig[:music_dir] }

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    Sources::Registry.reset!
    post session_path, params: { nick: "dj" }

    create(:track, :local, artist: "ABBA", album: "Gold", title: "Zither Tune",
                           source_uid: File.join(music_dir, "ABBA/Gold/z.mp3"),
                           local_path: File.join(music_dir, "ABBA/Gold/z.mp3"))
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([
      { source: "youtube", source_uid: "yt1", title: "Zither on YouTube", artist: "x", duration_ms: 1 }
    ])
  end

  after { Sources::Registry.reset! }

  it "shows album and folder links on a local result" do
    get search_path(q: "zither"), headers: { "Turbo-Frame" => "search_results" }
    # album link -> artists browse for ABBA / Gold
    expect(response.body).to include(CGI.escapeHTML(library_path(browse: "artists", artist: "ABBA", album: "Gold")))
    # folder link -> folders browse for ABBA/Gold
    expect(response.body).to include(CGI.escapeHTML(library_path(browse: "folders", path: "ABBA/Gold")))
    expect(response.body).to include("💿", "📁")
  end

  it "does not show album/folder links on a YouTube result" do
    get search_path(q: "zither"), headers: { "Turbo-Frame" => "search_results" }
    # the YouTube row has no folder link
    expect(response.body).not_to include(library_path(browse: "folders", path: "yt1"))
  end
end

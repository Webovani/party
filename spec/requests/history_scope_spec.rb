require "rails_helper"

RSpec.describe "History scoped search", type: :request do
  def search(params)
    get search_path(params), headers: { "Turbo-Frame" => "search_results" }
  end

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    Sources::Registry.reset!
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([])
    post session_path, params: { nick: "dj" }

    # Two played tracks (in history), one never played.
    @played_local = create(:track, :local, title: "Sandstorm", artist: "Darude")
    @played_yt    = create(:track, :youtube, title: "Sandcastle", artist: "YT Artist")
    @never        = create(:track, :local, title: "Sandbox", artist: "Nobody")
    create(:queue_item, track: @played_local, state: "played")
    create(:queue_item, track: @played_yt, state: "skipped")
  end

  after { Sources::Registry.reset! }

  it "restricts search to previously played tracks (any source)" do
    search(q: "sand", browse: "history")
    expect(response.body).to include("Sandstorm", "Sandcastle") # both in history
    expect(response.body).not_to include("Sandbox")             # never played
  end

  it "preserves a played track's real source for re-queueing" do
    search(q: "sandcastle", browse: "history")
    # the YouTube history hit re-queues as youtube (hidden field carries its source)
    expect(response.body).to include("value=\"youtube\"")
  end

  it "returns to the history view when the query is cleared while scoped" do
    search(q: "", browse: "history")
    expect(response).to redirect_to(history_path)
  end

  it "History frame declares the history scope for the search form" do
    get history_path, headers: { "Turbo-Frame" => "search_results" }
    expect(response.body).to include('data-scope-browse-value="history"')
    expect(response.body).to include('data-scope-label-value="History"')
  end
end

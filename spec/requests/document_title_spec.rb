require "rails_helper"

RSpec.describe "Browser tab title", type: :request do
  before { post session_path, params: { nick: "dj" } }

  def title(body) = body[%r{<title>(.*?)</title>}m, 1]

  def now_playing(track, status: "playing")
    item = create(:queue_item, track: track, queued_by: "dj", state: "playing")
    PlayerState.instance.update!(status: status, current_queue_item_id: item.id)
  end

  it "is just the app name when nothing is playing" do
    PlayerState.instance.update!(status: "stopped", current_queue_item_id: nil)
    get root_path
    expect(title(response.body)).to eq("Party")
  end

  it "shows the playing track, song first" do
    now_playing create(:track, :local, artist: "ABBA", title: "Dancing Queen")
    get root_path
    expect(title(response.body)).to eq("▶ ABBA – Dancing Queen · Party")
  end

  it "marks a paused track differently" do
    now_playing create(:track, :local, artist: "ABBA", title: "Dancing Queen"), status: "paused"
    get root_path
    expect(title(response.body)).to eq("⏸ ABBA – Dancing Queen · Party")
  end

  it "falls back to the app name when stopped mid-track" do
    now_playing create(:track, :local, artist: "ABBA", title: "Dancing Queen"), status: "stopped"
    get root_path
    expect(title(response.body)).to eq("Party")
  end

  it "copes with an untagged artist" do
    now_playing create(:track, :local, artist: nil, title: "untitled.mp3")
    get root_path
    expect(title(response.body)).to eq("▶ untitled.mp3 · Party")
  end

  it "escapes the track name rather than injecting markup into head" do
    now_playing create(:track, :local, artist: "AC/DC", title: "Rock & <Roll>")
    get root_path
    expect(response.body).to include("Rock &amp; &lt;Roll&gt;")
    expect(response.body).not_to include("<Roll>")
  end

  it "follows the track on every browse page, not just the root" do
    now_playing create(:track, :local, artist: "ABBA", title: "Dancing Queen")
    get "/library?browse=artists"
    expect(title(response.body)).to eq("▶ ABBA – Dancing Queen · Party")
  end
end

RSpec.describe "Tab title with self-describing titles", type: :request do
  before { post session_path, params: { nick: "dj" } }

  def title(body) = body[%r{<title>(.*?)</title>}m, 1]

  def now_playing(track)
    item = create(:queue_item, track: track, queued_by: "dj", state: "playing")
    PlayerState.instance.update!(status: "playing", current_queue_item_id: item.id)
  end

  # YouTube's "artist" is the uploading channel: either repeated in the video title
  # or not the artist at all. The tab title uses the video title alone.
  it "uses the video title alone for a YouTube track" do
    now_playing create(:track, source: "youtube", source_uid: "kp1",
                       artist: "Knife Party", title: "Knife Party - 'Internet Friends'")
    get root_path
    expect(title(response.body)).to eq("▶ Knife Party - &#39;Internet Friends&#39; · Party")
  end

  # A label channel is not the artist at all, so prefixing it would be worse than
  # redundant — it would be wrong.
  it "drops a label channel that is not the artist" do
    now_playing create(:track, source: "youtube", source_uid: "kp2",
                       artist: "AFM Records", title: "DYNAZTY - Waterfall")
    get root_path
    expect(title(response.body)).to eq("▶ DYNAZTY - Waterfall · Party")
  end

  it "still prefixes the artist for local tracks, whose tags are trustworthy" do
    now_playing create(:track, :local, artist: "ABBA", title: "Dancing Queen")
    get root_path
    expect(title(response.body)).to eq("▶ ABBA – Dancing Queen · Party")
  end
end

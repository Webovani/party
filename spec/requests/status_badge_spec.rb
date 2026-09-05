require "rails_helper"

# The badge answers "why hasn't my song started". Nothing plays before it says
# ready, because the daemon parks on anything not playable.
RSpec.describe "Queue status badge", type: :request do
  before { post session_path, params: { nick: "dj" } }

  let(:music) { Rails.root.join("tmp/test_music").tap { |d| FileUtils.mkdir_p(d) } }
  def on_disk = music.join("s#{SecureRandom.hex(4)}.mp3").tap { |f| File.write(f, "x") }.to_s

  def badge_for(track)
    create(:queue_item, queued_by: "dj", track: track)
    get queue_region_path
    response.body[%r{<span class="badge (\w+)"[^>]*>\s*([^<]+?)\s*</span>}m, 2]
  end

  it "says downloading while a YouTube track is being fetched" do
    expect(badge_for(create(:track, source: "youtube", source_uid: "a", cache_status: "pending")))
      .to eq("downloading…")
  end

  it "says queued before the download has started" do
    expect(badge_for(create(:track, source: "youtube", source_uid: "b", cache_status: "none")))
      .to eq("queued")
  end

  it "says failed when the download gave up" do
    expect(badge_for(create(:track, source: "youtube", source_uid: "c", cache_status: "error")))
      .to eq("failed")
  end

  # The step that used to be invisible: downloaded, but still unplayable.
  it "says measuring once downloaded but not yet measured" do
    track = create(:track, source: "youtube", source_uid: "d", cache_status: "ready",
                   cache_path: on_disk, loudness_lufs: nil)
    expect(badge_for(track)).to eq("measuring…")
  end

  it "says measuring for a local file that hasn't been measured" do
    expect(badge_for(create(:track, :local, local_path: on_disk, loudness_lufs: nil)))
      .to eq("measuring…")
  end

  it "says ready only when it could actually start" do
    track = create(:track, :local, local_path: on_disk, loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
    expect(badge_for(track)).to eq("ready")
    expect(track).to be_playable
  end

  it "flags a local file that has gone missing" do
    expect(badge_for(create(:track, :local, loudness_lufs: -12.0, loudness_lufs_hp: -14.0)))
      .to eq("missing")
  end
end

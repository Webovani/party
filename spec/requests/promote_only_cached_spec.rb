require "rails_helper"

# Promoting sends an item to the head, and the player waits on an unready head
# rather than skipping it — so promoting a still-downloading track stalls playback
# until (or unless) the download lands.
RSpec.describe "Promoting a track that isn't downloaded yet", type: :request do
  before do
    post session_path, params: { nick: "dj" }
    allow(PlayerCommands).to receive(:notify).and_return(true)
    create(:queue_item, queued_by: "alice", track: create(:track, :local))
  end

  # The :local factory points at /media/music, which isn't there in tests — and
  # ready_to_play? stats the file, so this needs a real one.
  def on_disk
    dir = Rails.root.join("tmp/test_music")
    FileUtils.mkdir_p(dir)
    dir.join("ready-#{SecureRandom.hex(4)}.mp3").tap { |f| File.write(f, "x") }.to_s
  end

  def pending_youtube
    create(:queue_item, queued_by: "dj",
           track: create(:track, source: "youtube", source_uid: "vid1",
                         title: "Still downloading", cache_status: "pending"))
  end

  it "refuses, and says why" do
    item = pending_youtube

    expect { post move_to_front_queue_item_path(item) }
      .not_to change { item.reload.state }
    expect(response.body).to include("Not ready yet")
  end

  it "does not burn the mover's 30-minute cooldown on a refusal" do
    item = pending_youtube
    post move_to_front_queue_item_path(item)

    expect(User.find_by(nick: "dj").moved_at).to be_nil
  end

  it "hides the ⤒ button for a track that isn't ready" do
    pending_youtube
    get root_path

    rows = response.body.scan(%r{<li class="qitem".*?</li>}m)
    row = rows.find { |r| r.include?("Still downloading") }
    expect(row).not_to include("Play next")
  end

  it "refuses a downloaded track that has not been measured yet" do
    item = create(:queue_item, queued_by: "dj",
                  track: create(:track, :local, local_path: on_disk, loudness_lufs: nil))

    expect { post move_to_front_queue_item_path(item) }.not_to change { item.reload.state }
    expect(response.body).to include("Not ready yet")
  end

  it "still allows promoting a track that is downloaded AND measured" do
    ready = create(:queue_item, queued_by: "dj",
                   track: create(:track, :local, local_path: on_disk,
                                 loudness_lufs: -12.0, loudness_lufs_hp: -14.0))

    expect { post move_to_front_queue_item_path(ready) }
      .to change { ready.reload.state }.to("promoted")
    expect(User.find_by(nick: "dj").moved_at).to be_present
  end

  # Same rule, same reason: the daemon parks on an unready head whatever the
  # source, so a local file on an unmounted drive can't be promoted either.
  it "refuses a local track whose file has gone missing" do
    gone = create(:queue_item, queued_by: "dj", track: create(:track, :local))

    expect { post move_to_front_queue_item_path(gone) }.not_to change { gone.reload.state }
  end
end

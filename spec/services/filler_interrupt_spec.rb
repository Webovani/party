require "rails_helper"

# The daemon's filler logic, exercised through the real objects with mpv stubbed.
RSpec.describe PlayerDaemon, "filler interruption" do
  let(:mpv) { instance_double("MpvClient") }
  let(:daemon) { described_class.allocate }
  let(:music) { Rails.root.join("tmp/test_music").tap { |d| FileUtils.mkdir_p(d) } }

  def on_disk = music.join("f#{SecureRandom.hex(4)}.mp3").tap { |f| File.write(f, "x") }.to_s

  def measured(duration_ms)
    create(:track, :local, local_path: on_disk, duration_ms: duration_ms,
           loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
  end

  before do
    allow(PartyBroadcaster).to receive(:refresh)
    allow(PlayerCommands).to receive(:notify).and_return(true)
    allow(mpv).to receive(:loadfile)
    allow(mpv).to receive(:set_property)
    allow(mpv).to receive(:command)
    daemon.instance_variable_set(:@mpv, mpv)
    daemon.instance_variable_set(:@lock, Mutex.new)
    daemon.instance_variable_set(:@stopping, false)
    daemon.instance_variable_set(:@graceful, false)
  end

  def start_playing(item)
    item.update!(state: "playing")
    PlayerState.instance.update!(status: "playing", current_queue_item_id: item.id)
    daemon.instance_variable_set(:@loaded_item_id, item.id)
  end

  it "steps aside when a real track arrives, saving its position" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000))
    start_playing(filler)
    allow(mpv).to receive(:get_property).with("time-pos").and_return(612.5)

    normal = create(:queue_item, queued_by: "alice", track: measured(3 * 60 * 1000))
    daemon.send(:do_queue_changed)

    expect(filler.reload).to have_attributes(state: "queued", resume_position_ms: 612_500)
    expect(normal.reload.state).to eq("playing")
  end

  it "resumes from the saved position rather than restarting the mix" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000),
                    resume_position_ms: 612_500)

    expect(mpv).to receive(:loadfile).with(filler.track.playable_path, start_seconds: 612.5)
    daemon.send(:play_item, PlayerState.instance, filler, filler.track)
    expect(PlayerState.instance.position_ms).to eq(612_500)
  end

  it "leaves a filler alone when nothing else is waiting" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000))
    start_playing(filler)

    expect(daemon.send(:interrupt_filler)).to be false
    expect(filler.reload.state).to eq("playing")
  end

  it "does not interrupt a normal track when another is queued" do
    normal = create(:queue_item, queued_by: "dj", track: measured(3 * 60 * 1000))
    start_playing(normal)
    create(:queue_item, queued_by: "alice", track: measured(3 * 60 * 1000))

    expect(daemon.send(:interrupt_filler)).to be false
    expect(normal.reload.state).to eq("playing")
  end

  # Stepping aside for a track that cannot start would turn a playing mix into
  # silence, which is worse than letting it run on.
  it "keeps playing when the waiting track is not ready yet" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000))
    start_playing(filler)
    create(:queue_item, queued_by: "alice",
           track: create(:track, :local, local_path: on_disk, duration_ms: 180_000,
                         loudness_lufs: nil, loudness_lufs_hp: nil))

    expect(daemon.send(:interrupt_filler)).to be false
    expect(filler.reload.state).to eq("playing")
  end

  it "steps aside once that track becomes ready" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000))
    start_playing(filler)
    allow(mpv).to receive(:get_property).with("time-pos").and_return(30.0)
    waiting = create(:queue_item, queued_by: "alice", track: measured(180_000))

    expect(daemon.send(:interrupt_filler)).to be true
    expect(waiting.reload.state).to eq("playing")
  end

  it "is not displaced by another filler" do
    filler = create(:queue_item, queued_by: "dj", track: measured(45 * 60 * 1000))
    start_playing(filler)
    create(:queue_item, queued_by: "alice", track: measured(50 * 60 * 1000))

    expect(daemon.send(:interrupt_filler)).to be false
  end
end

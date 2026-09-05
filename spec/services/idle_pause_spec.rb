require "rails_helper"

RSpec.describe PlayerDaemon, "paused with nothing loaded" do
  let(:mpv) { instance_double("MpvClient") }
  let(:daemon) { described_class.allocate }
  let(:music) { Rails.root.join("tmp/test_music").tap { |d| FileUtils.mkdir_p(d) } }

  def on_disk = music.join("p#{SecureRandom.hex(4)}.mp3").tap { |f| File.write(f, "x") }.to_s

  def measured
    create(:track, :local, local_path: on_disk, duration_ms: 180_000,
           loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
  end

  before do
    allow(PartyBroadcaster).to receive(:reload)
    allow(PlayerCommands).to receive(:notify).and_return(true)
    allow(mpv).to receive(:loadfile)
    allow(mpv).to receive(:set_property)
    allow(mpv).to receive(:command)
    allow(mpv).to receive(:stop)
    allow(mpv).to receive(:get_property).and_return(0.0)
    daemon.instance_variable_set(:@mpv, mpv)
    daemon.instance_variable_set(:@lock, Mutex.new)
    daemon.instance_variable_set(:@stopping, false)
    daemon.instance_variable_set(:@graceful, false)
    daemon.instance_variable_set(:@loaded_item_id, nil)
    allow(daemon).to receive(:mpv_alive?).and_return(true)
  end

  it "starts the queue when a track is added" do
    PlayerState.instance.update!(status: "paused", current_queue_item_id: nil)
    item = create(:queue_item, queued_by: "dj", track: measured)

    daemon.send(:do_queue_changed)

    expect(item.reload.state).to eq("playing")
  end

  it "picks the queue up on the next tick, with no one pressing anything" do
    PlayerState.instance.update!(status: "paused", current_queue_item_id: nil)
    item = create(:queue_item, queued_by: "dj", track: measured)

    daemon.send(:tick)

    expect(item.reload.state).to eq("playing")
  end

  it "leaves a genuinely paused song paused" do
    item = create(:queue_item, queued_by: "dj", track: measured)
    item.update!(state: "playing")
    PlayerState.instance.update!(status: "paused", current_queue_item_id: item.id)
    daemon.instance_variable_set(:@loaded_item_id, item.id)
    later = create(:queue_item, queued_by: "ann", track: measured)

    daemon.send(:do_queue_changed)
    daemon.send(:tick)

    expect(later.reload.state).to eq("queued")
    expect(PlayerState.instance.status).to eq("paused")
  end

  it "leaves an explicitly stopped player alone" do
    PlayerState.instance.update!(status: "stopped", current_queue_item_id: nil)
    item = create(:queue_item, queued_by: "dj", track: measured)

    daemon.send(:tick)

    expect(item.reload.state).to eq("queued")
  end
end

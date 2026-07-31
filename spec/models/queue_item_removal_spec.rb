require "rails_helper"

RSpec.describe QueueItem, "re-dealing after a removal" do
  def enqueue(nick, n = 1)
    Array.new(n) { create(:queue_item, queued_by: nick, track: create(:track, :local)) }
  end

  def order = QueueItem.waiting.map { |i| [i.queued_by, i.position] }

  it "re-deals when an item is destroyed (positions stay contiguous)" do
    enqueue("alice", 3)
    enqueue("bob", 2)
    victim = QueueItem.waiting.to_a[2]

    victim.destroy

    positions = order.map(&:last)
    expect(positions).to eq((positions.first..positions.first + positions.size - 1).to_a),
      "expected a re-deal to close the gap, got #{order.inspect}"
  end

  it "coalesces a bulk removal into a single re-deal" do
    enqueue("alice", 3)
    enqueue("bob", 3)

    deals = 0
    allow(QueueItem).to receive(:deal!).and_wrap_original { |m, *a| deals += 1; m.call(*a) }

    QueueItem.transaction { QueueItem.where(queued_by: "bob").destroy_all }

    expect(deals).to eq(1)
    expect(order.map(&:first)).to all(eq("alice"))
  end

  it "re-deals when an undownloadable YouTube track is dropped" do
    enqueue("alice", 2)
    track = create(:track, :youtube, cache_status: "error", cache_attempts: 2)
    create(:queue_item, queued_by: "bob", track: track)

    expect { QueueItem.where(track: track).destroy_all }
      .to change { QueueItem.waiting.count }.by(-1)
    expect(order.map(&:first)).to eq(%w[alice alice])
  end

  it "leaves the playing item's position alone" do
    playing = create(:queue_item, queued_by: "alice", track: create(:track, :local), state: "playing")
    enqueue("bob", 2)

    expect { QueueItem.waiting.last.destroy }.not_to change { playing.reload.position }
  end
end

RSpec.describe CacheYoutubeTrackJob, "dropping a broken video" do
  it "drops it even when it was promoted to the front" do
    create(:queue_item, queued_by: "alice", track: create(:track, :local))
    track = create(:track, :youtube, cache_attempts: 1)
    create(:queue_item, queued_by: "bob", track: track, state: "promoted")

    allow_any_instance_of(YoutubeDownloader).to receive(:cached_file).and_return(nil)
    allow_any_instance_of(YoutubeDownloader).to receive(:download).and_raise("410 Gone")
    allow(PlayerCommands).to receive(:notify).and_return(true)

    expect { described_class.perform_now(track.id) }
      .to change { QueueItem.active.where(track: track).count }.from(1).to(0)
  end
end

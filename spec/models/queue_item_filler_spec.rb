require "rails_helper"

# A long track (a mix) is filler: it plays only when nothing else is waiting, and
# steps aside — position saved — as soon as anyone queues a real song.
RSpec.describe QueueItem, "filler" do
  def long  = create(:track, :local, duration_ms: 45 * 60 * 1000, title: "Deep Mix")
  def short = create(:track, :local, duration_ms: 3 * 60 * 1000)

  def add(nick, track) = create(:queue_item, queued_by: nick, track: track)
  def order = QueueItem.waiting.map { |i| i.filler? ? "FILLER" : i.queued_by }

  it "flags a track over the threshold on the way in" do
    expect(add("dj", long)).to be_filler
    expect(add("dj", short)).not_to be_filler
  end

  it "uses the configured threshold, decided once at add time" do
    item = add("dj", create(:track, :local, duration_ms: 11 * 60 * 1000))
    expect(item).not_to be_filler
  end

  it "sorts behind every normal track no matter when it was added" do
    add("dj", long)
    add("alice", short)
    add("bob", short)

    expect(order).to eq(%w[alice bob FILLER])
  end

  it "is not reached by head while anything else waits" do
    filler = add("dj", long)
    normal = add("alice", short)

    expect(QueueItem.head).to eq(normal)
    normal.update!(state: "played")
    expect(QueueItem.head).to eq(filler)
  end

  it "does not consume its owner's turn in the round-robin" do
    add("dj", long)      # dj's filler must not cost dj a slot
    add("dj", short)
    add("alice", short)

    expect(order).to eq(%w[dj alice FILLER])
  end

  it "keeps several fillers in their own order behind the rest" do
    f1 = add("dj", long)
    f2 = add("alice", long)
    add("bob", short)

    expect(QueueItem.waiting.last(2)).to eq([f1, f2])
  end
end

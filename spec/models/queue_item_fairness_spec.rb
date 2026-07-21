require "rails_helper"

RSpec.describe "QueueItem fair ordering", type: :model do
  def enqueue(nick)
    create(:queue_item, queued_by: nick, track: create(:track, :local))
  end

  def order = QueueItem.waiting.map(&:queued_by)

  describe "a newcomer appends to the current round (never jumps the front)" do
    it "lands behind nicks that still have a slot left in this round" do
      a1 = enqueue("alice"); enqueue("bob"); enqueue("derek")
      a1.update!(state: "playing") # alice has now taken her slot in this round
      enqueue("carol")             # newcomer arrives mid-round

      # bob and derek still owe this round, so carol goes after them — not first
      expect(QueueItem.queued.map(&:queued_by)).to eq(%w[bob derek carol])
    end

    it "with nothing playing, nobody has taken a slot, so it appends at the back" do
      enqueue("alice"); enqueue("bob")
      enqueue("carol")
      expect(order.first(3)).to eq(%w[alice bob carol])
    end

    it "is only 'first' when everyone else already took their slot this round" do
      a1 = enqueue("alice"); b1 = enqueue("bob")
      enqueue("alice"); enqueue("bob") # their 2nd songs (next round)
      a1.update!(state: "playing")
      b1.update!(state: "promoted")    # both took this round's slot
      enqueue("carol")

      # carol completes the round; alice/bob's 2nd songs are the next round
      expect(QueueItem.queued.map(&:queued_by)).to eq(%w[carol alice bob])
    end
  end

  it "interleaves by nick (everyone's 1st before anyone's 2nd)" do
    # Alice piles on first, then Bob adds one.
    enqueue("alice"); enqueue("alice"); enqueue("alice"); enqueue("bob")
    expect(order).to eq(%w[alice bob alice alice])
  end

  it "keeps enqueue order within a rank tier" do
    a1 = enqueue("alice"); b1 = enqueue("bob"); c1 = enqueue("carol")
    a2 = enqueue("alice"); b2 = enqueue("bob")
    expect(QueueItem.waiting).to eq([a1, b1, c1, a2, b2])
  end

  it "counts the currently-playing nick so they don't get back-to-back turns" do
    create(:queue_item, queued_by: "alice", track: create(:track, :local), state: "playing")
    a1 = enqueue("alice")
    b1 = enqueue("bob")
    # Without counting the playing song, alice would be on top (tie by enqueue).
    # Counting it pushes alice's next song behind bob's.
    expect(QueueItem.waiting).to eq([b1, a1])
    expect(QueueItem.head).to eq(b1)
  end

  it "gives a brand-new nick a head start over a heavy queuer" do
    3.times { enqueue("alice") }
    newcomer = enqueue("dave")
    expect(QueueItem.head).to eq(QueueItem.where(queued_by: "alice").order(:position).first)
    # dave's single song is 2nd overall — ahead of alice's 2nd and 3rd
    expect(order).to eq(%w[alice dave alice alice])
  end

  it "puts a 'play next' (promoted) item at the very front regardless of fairness" do
    enqueue("alice"); enqueue("bob")
    promoted = enqueue("alice") # alice's 2nd, normally last
    promoted.move_to_front!
    expect(QueueItem.head).to eq(promoted)
    expect(order.first).to eq("alice")
  end

  it "honors the most recent 'play next' as the next slot" do
    x = enqueue("alice"); y = enqueue("bob")
    x.move_to_front!
    y.move_to_front! # y promoted after x => y plays next
    expect(QueueItem.waiting.first(2)).to eq([y, x])
  end

  describe "a promoted song seeds the round-robin (and stays on top)" do
    it "pushes the promoter's other songs behind other nicks" do
      a1 = enqueue("alice"); a2 = enqueue("alice")
      expect(QueueItem.waiting.to_a).to eq([a1, a2])
      expect(QueueItem.head).to eq(a1)

      b1 = enqueue("bob")
      expect(QueueItem.waiting.to_a).to eq([a1, b1, a2])
      expect(QueueItem.head).to eq(a1)

      a2.move_to_front! # promote alice's 2nd to the top
      expect(QueueItem.waiting.to_a).to eq([a2.reload, b1.reload, a1.reload])
      expect(QueueItem.head).to eq(a2)
    end

    it "defers the promoter by only ONE round no matter how many it promotes" do
      a1 = enqueue("alice")
      b1 = enqueue("bob"); b2 = enqueue("bob")
      p1 = enqueue("alice"); p2 = enqueue("alice")
      p1.move_to_front!; p2.move_to_front! # alice promotes two songs to the top

      normal = QueueItem.queued
      # deferred by one round only: bob, alice, bob  (NOT bob, bob, alice)
      expect(normal).to eq([b1, a1, b2])
    end

    it "pops newcomers to the front in queue order, ahead of played nicks but not each other" do
      # head: alice playing, bob & alice promoted
      create(:queue_item, queued_by: "alice", track: create(:track, :local), state: "playing")
      enqueue("bob").move_to_front!     # promoted to first
      enqueue("alice").move_to_front!   # promoted to first
      # head: alice1, alice2, bob1 (alice will keep spot in front of bob)
      # tail: bob2, alice3, then two newcomers (derek queued before carol)
      bob2   = enqueue("bob")
      alice3 = enqueue("alice")
      derek1 = enqueue("derek")
      carol1 = enqueue("carol")

      expect(QueueItem.queued.to_a).to eq([derek1, carol1, alice3, bob2])
    end
  end

  describe "stability" do
    it "inserting a song only inserts it — existing order is untouched" do
      enqueue("alice"); enqueue("bob"); enqueue("alice")
      before = QueueItem.waiting.to_a
      newcomer = enqueue("carol")
      after = QueueItem.waiting.to_a
      # removing the newcomer from the new order reproduces the old order exactly
      expect(after - [newcomer]).to eq(before)
      expect(after).to include(newcomer)
    end

    it "consuming the head only shifts — the remainder keeps its order" do
      a1 = enqueue("alice"); enqueue("alice"); enqueue("bob")
      before_tail = QueueItem.waiting.drop(1) # everything after the head

      # Consume the head the way the player does: it becomes the playing song
      # (which then seeds the round-robin).
      a1.update!(state: "playing")

      expect(QueueItem.waiting).to eq(before_tail)
    end
  end

  describe ".reshuffle!" do
    # A queue whose fair order is round-robin iff, walking it in order, each item's
    # per-nick rank never decreases (all rank-0 before any rank-1, etc.).
    def round_robin_intact?
      seen = Hash.new(0)
      ranks = QueueItem.waiting.map do |item|
        r = seen[item.queued_by]; seen[item.queued_by] += 1; r
      end
      ranks == ranks.sort
    end

    before { 4.times { enqueue("alice") }; 3.times { enqueue("bob") }; 2.times { enqueue("carol") } }

    it "keeps the round-robin invariant after shuffling" do
      10.times do
        QueueItem.reshuffle!
        expect(round_robin_intact?).to be(true)
      end
    end

    it "preserves the exact set of queued items" do
      before_ids = QueueItem.queued.pluck(:id).sort
      QueueItem.reshuffle!
      expect(QueueItem.queued.pluck(:id).sort).to eq(before_ids)
    end

    it "actually changes the order at least sometimes" do
      original = QueueItem.waiting.map(&:id)
      changed = (1..15).any? { QueueItem.reshuffle!; QueueItem.waiting.map(&:id) != original }
      expect(changed).to be(true)
    end

    it "leaves a promoted 'play next' item at the front" do
      promoted = QueueItem.where(queued_by: "bob").last
      promoted.move_to_front!
      QueueItem.reshuffle!
      expect(QueueItem.head).to eq(promoted)
    end
  end
end

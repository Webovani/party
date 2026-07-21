require "rails_helper"

RSpec.describe "Queue flow", type: :request do
  # Sign in by posting a nick (sets the signed cookie the way the app does).
  def sign_in(nick = "dj")
    post session_path, params: { nick: nick }
  end

  def add_youtube(uid: "abc123", title: "Some Song")
    post queue_items_path, params: {
      source: "youtube", source_uid: uid, title: title, artist: "Artist", duration_ms: 200_000
    }
  end

  before { allow(PlayerCommands).to receive(:notify).and_return(true) }

  describe "nickname gate" do
    it "rejects queueing without a nick" do
      add_youtube
      expect(response).to redirect_to(root_path)
      expect(QueueItem.count).to eq(0)
    end

    it "accepts a valid nick and sets the cookie" do
      sign_in("Party DJ")
      expect(User.exists?(nick: "Party DJ")).to be(true)
    end
  end

  describe "enqueue + fair use" do
    before { sign_in }

    it "adds a track to the queue and upserts the Track" do
      expect { add_youtube }.to change(QueueItem, :count).by(1)
      expect(Track.youtube.find_by(source_uid: "abc123")).to be_present
    end

    it "triggers caching for youtube tracks" do
      expect { add_youtube }.to have_enqueued_job(PrecacheQueueJob)
    end

    it "rejects a duplicate of an already-queued track" do
      add_youtube(uid: "dup1")
      expect { add_youtube(uid: "dup1") }.not_to change(QueueItem, :count)
    end

    it "enforces the per-user pending limit" do
      stub_const_config(max_queue_per_user: 2)
      add_youtube(uid: "a"); add_youtube(uid: "b")
      expect { add_youtube(uid: "c") }.not_to change(QueueItem, :count)
    end

    it "enforces the total queue length" do
      stub_const_config(max_queue_length: 1)
      add_youtube(uid: "a")
      expect { add_youtube(uid: "b") }.not_to change(QueueItem, :count)
    end
  end

  describe "queue management" do
    before { sign_in }

    it "moves an item to the front" do
      add_youtube(uid: "first"); add_youtube(uid: "second")
      last = QueueItem.order(:position).last
      post move_to_front_queue_item_path(last)
      expect(QueueItem.waiting.first).to eq(last)
    end
  end

  describe "skip voting" do
    before { sign_in }

    it "skips once the vote threshold is reached" do
      stub_const_config(votes_to_skip: 2)
      item = create(:queue_item, track: create(:track, :youtube))
      PlayerState.instance.update!(current_queue_item_id: item.id, status: "playing")

      expect(PlayerCommands).to receive(:skip)
      post skip_votes_path                              # vote 1 (dj)
      sign_in("raver"); post skip_votes_path            # vote 2 (raver) -> skip
    end
  end

  # Override PartyConfig values for one example.
  def stub_const_config(overrides)
    merged = Rails.application.config.party.merge(overrides.transform_keys(&:to_sym))
    allow(Rails.application.config).to receive(:party).and_return(merged)
  end
end

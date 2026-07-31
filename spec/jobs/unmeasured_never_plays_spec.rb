require "rails_helper"

# Playing an unmeasured track means playing at gain 0 — full volume — at the exact
# moment we know least about it. The player parks instead, so the queue must not be
# able to park forever on something ffmpeg cannot read.
RSpec.describe "Never play an unmeasured track" do
  let(:music) { Rails.root.join("tmp/test_music").tap { |d| FileUtils.mkdir_p(d) } }

  def on_disk(name = "t#{SecureRandom.hex(4)}.mp3")
    music.join(name).tap { |f| File.write(f, "x") }.to_s
  end

  describe Track, "#playable?" do
    it "is false while the file is there but the loudness isn't known" do
      t = build(:track, :local, local_path: on_disk, loudness_lufs: nil, loudness_lufs_hp: nil)
      expect(t.ready_to_play?).to be true
      expect(t).not_to be_playable
    end

    it "is false when only the first measurement pass exists" do
      t = build(:track, :local, local_path: on_disk, loudness_lufs: -12.0, loudness_lufs_hp: nil)
      expect(t).not_to be_playable
    end

    it "is true once both passes are stored" do
      t = build(:track, :local, local_path: on_disk, loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
      expect(t).to be_playable
    end

    it "is false when the file is missing, however well measured" do
      t = build(:track, :local, loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
      expect(t).not_to be_playable
    end
  end

  describe AnalyzeLoudnessJob do
    before do
      allow(PartyBroadcaster).to receive(:refresh)
      allow(PlayerCommands).to receive(:notify).and_return(true)
    end

    it "wakes the parked player once the measurement lands" do
      track = create(:track, :local, local_path: on_disk, loudness_lufs: nil)
      allow_any_instance_of(LoudnessAnalyzer).to receive(:measure)
        .and_return(lufs: -12.0, lufs_hp: -14.0)

      expect(PlayerCommands).to receive(:queue_changed)
      described_class.perform_now(track.id)
      expect(track.reload).to be_playable
    end

    it "counts a failed measurement instead of leaving it at zero attempts" do
      track = create(:track, :local, local_path: on_disk, loudness_lufs: nil)
      allow_any_instance_of(LoudnessAnalyzer).to receive(:measure).and_return(nil)

      described_class.perform_now(track.id)
      expect(track.reload.loudness_attempts).to eq(1)
      expect(QueueItem.count).to eq(0)
    end

    it "drops an unmeasurable track from the queue rather than parking the head forever" do
      track = create(:track, :local, local_path: on_disk, loudness_lufs: nil, loudness_attempts: 1)
      create(:queue_item, queued_by: "dj", track: track, state: "promoted")
      allow_any_instance_of(LoudnessAnalyzer).to receive(:measure).and_return(nil)

      expect { described_class.perform_now(track.id) }
        .to change { QueueItem.active.where(track: track).count }.from(1).to(0)
    end
  end
end

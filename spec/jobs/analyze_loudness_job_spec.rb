require "rails_helper"

RSpec.describe AnalyzeLoudnessJob, type: :job do
  before { allow(PartyBroadcaster).to receive(:reload) }

  it "measures and stores loudness for a playable track" do
    track = create(:track, :local, loudness_lufs: nil)
    allow_any_instance_of(Track).to receive(:ready_to_play?).and_return(true)
    allow_any_instance_of(LoudnessAnalyzer).to receive(:measure).and_return(lufs: -14.9, lufs_hp: -17.4)

    described_class.perform_now(track.id)
    expect(track.reload).to have_attributes(loudness_lufs: -14.9, loudness_lufs_hp: -17.4)
    expect(track.bass_share_db).to be_within(0.01).of(2.5)
  end

  it "skips a track that is already measured" do
    track = create(:track, :local, loudness_lufs: -12.0, loudness_lufs_hp: -14.0)
    expect_any_instance_of(LoudnessAnalyzer).not_to receive(:measure)

    described_class.perform_now(track.id)
    expect(track.reload.loudness_lufs).to eq(-12.0)
  end

  it "skips a youtube track whose file isn't cached yet" do
    track = create(:track, source: "youtube", cache_status: "none", loudness_lufs: nil)
    expect_any_instance_of(LoudnessAnalyzer).not_to receive(:measure)

    described_class.perform_now(track.id)
    expect(track.reload.loudness_lufs).to be_nil
  end

  it "leaves loudness nil when the measurement fails" do
    track = create(:track, :local, loudness_lufs: nil)
    allow_any_instance_of(Track).to receive(:ready_to_play?).and_return(true)
    allow_any_instance_of(LoudnessAnalyzer).to receive(:measure).and_return(nil)

    described_class.perform_now(track.id)
    expect(track.reload.loudness_lufs).to be_nil
  end

  it "re-measures a track that predates the highpass pass" do
    track = create(:track, :local, loudness_lufs: -12.0, loudness_lufs_hp: nil)
    allow_any_instance_of(Track).to receive(:ready_to_play?).and_return(true)
    allow_any_instance_of(LoudnessAnalyzer).to receive(:measure).and_return(lufs: -12.0, lufs_hp: -16.3)

    described_class.perform_now(track.id)
    expect(track.reload.loudness_lufs_hp).to eq(-16.3)
  end
end

RSpec.describe LoudnessAnalyzer do
  it "parses the integrated loudness out of ffmpeg's summary" do
    output = <<~OUT
      [Parsed_ebur128_0 @ 0x55] t: 60  TARGET:-23 LUFS  M: -14.9 S: -16.5  I: -16.0 LUFS  LRA: 3.3 LU
      [Parsed_ebur128_0 @ 0x55] Summary:

        Integrated loudness:
          I:         -14.9 LUFS
          Threshold: -26.0 LUFS

        Loudness range:
          LRA:         3.3 LU
    OUT
    expect(described_class.new.send(:parse_integrated, output)).to eq(-14.9)
  end

  it "returns nil for a missing file without shelling out" do
    expect(described_class.new.measure("/no/such/file.mp3")).to be_nil
  end
end

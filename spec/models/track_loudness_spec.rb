require "rails_helper"

RSpec.describe "Track loudness gain", type: :model do
  # defaults: target -20 LUFS, gain clamped to [-20, 0] (attenuation only)
  it "attenuates a loud track down to the target" do
    t = build(:track, :local, loudness_lufs: -8.5)
    expect(t.loudness_gain_db).to be_within(0.01).of(-11.5)
  end

  it "never amplifies — a quiet track is left alone (conservative headroom)" do
    t = build(:track, :local, loudness_lufs: -23.7)
    expect(t.loudness_gain_db).to eq(0.0)
  end

  it "is a no-op for an unmeasured track" do
    t = build(:track, :local, loudness_lufs: nil)
    expect(t.loudness_gain_db).to eq(0.0)
  end

  it "clamps absurdly loud material to the floor" do
    t = build(:track, :local, loudness_lufs: 5.0) # would want -25 dB
    expect(t.loudness_gain_db).to eq(-20.0)
  end

  # The gain is applied as dB by mpv's volume FILTER, never by folding it into
  # mpv's "volume" property — that property is a cubic scale, so an amplitude
  # factor there lands 3x too hard in dB.
  it "is expressed in dB, independent of the user's volume" do
    t = build(:track, :local, loudness_lufs: -14.0)
    expect(t.loudness_gain_db).to be_within(0.01).of(-6.0)
    expect(t).not_to respond_to(:loudness_scale)
  end
end

RSpec.describe "Track bass correction", type: :model do
  # default correction 0.5: half the sub-bass share is discounted
  def track(lufs, hp) = build(:track, :local, loudness_lufs: lufs, loudness_lufs_hp: hp)

  it "gives a bass-heavy track more gain than a midrange one at equal LUFS" do
    psy  = track(-12.0, -17.0) # 5 dB of bass
    pop  = track(-12.0, -12.7) # 0.7 dB of bass

    expect(psy.bass_share_db).to be_within(0.01).of(5.0)
    expect(psy.loudness_gain_db).to be > pop.loudness_gain_db
    # half of the 4.3 dB bass-share difference
    expect(psy.loudness_gain_db - pop.loudness_gain_db).to be_within(0.01).of(2.15)
  end

  it "falls back to plain R128 when only the first pass exists" do
    t = track(-12.5, nil)
    expect(t.bass_share_db).to eq(0.0)
    expect(t.loudness_gain_db).to be_within(0.01).of(-7.5)
    expect(t).not_to be_loudness_measured
  end

  it "ignores a negative bass share (gating noise, not signal)" do
    expect(track(-12.0, -11.8).bass_share_db).to eq(0.0)
  end

  it "honours the correction knob" do
    t = track(-12.0, -17.0)
    allow(PartyConfig).to receive(:fetch).and_call_original
    allow(PartyConfig).to receive(:fetch).with(:loudness_bass_correction, anything).and_return(0.0)
    expect(t.effective_loudness_lufs).to be_within(0.01).of(-12.0)

    allow(PartyConfig).to receive(:fetch).with(:loudness_bass_correction, anything).and_return(1.0)
    expect(t.effective_loudness_lufs).to be_within(0.01).of(-17.0)
  end
end

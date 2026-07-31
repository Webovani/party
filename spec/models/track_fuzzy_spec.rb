require "rails_helper"

RSpec.describe Track, "fuzzy search" do
  before do
    create(:track, :local, artist: "Jaromír Nohavica", title: "Empire State", album: "Divné století")
    create(:track, :local, artist: "ABBA", title: "Dancing Queen", album: "Arrival")
    create(:track, :local, artist: "Blur", title: "Song 2", album: "Parklife")
  end

  def titles(rel) = rel.map(&:title)

  it "prefers exact/prefix matches and does not go fuzzy when they exist" do
    expect(titles(Track.local.matching("danc"))).to eq(["Dancing Queen"])
  end

  it "recovers a transposed typo that prefix matching cannot" do
    expect(Track.local.search("nohavcia")).to be_empty
    expect(titles(Track.local.matching("nohavcia"))).to eq(["Empire State"])
  end

  it "recovers a dropped letter" do
    expect(titles(Track.local.matching("nohvica"))).to eq(["Empire State"])
  end

  # Diacritics are stripped at INDEX time, so this is an exact FTS hit — not
  # something the fuzzy fallback has to rescue.
  it "ignores diacritics entirely, on the exact path" do
    expect(titles(Track.local.search("jaromir"))).to eq(["Empire State"])
    expect(titles(Track.local.search("stoleti"))).to eq(["Empire State"]) # album
  end

  it "matches accented input against unaccented storage and vice versa" do
    create(:track, :local, artist: "Cechomor", title: "Plovou mraky")
    expect(titles(Track.local.search("čechomor"))).to eq(["Plovou mraky"])
  end

  it "handles sloppy typing across artist AND title together" do
    # exact artist + transposed title (0.500), and no-diacritics artist + truncated title
    expect(titles(Track.local.matching("abba dancnig"))).to eq(["Dancing Queen"])
    expect(titles(Track.local.matching("jaromir empir"))).to eq(["Empire State"])
  end

  # Known limit: two transposed letters in a short word land at 0.375, just under
  # the threshold ("jarmoir", "empries"). Dropping to 0.3 to catch them made
  # nonsense queries match the whole library, which is the worse failure.
  it "does not stretch to a double transposition" do
    expect(Track.local.matching("jarmoir")).to be_empty
    expect(Track.local.matching("empries")).to be_empty
  end

  it "still requires every term to match something" do
    expect(Track.local.matching("nohavica parklife")).to be_empty
  end

  it "rejects noise rather than returning the whole library" do
    expect(Track.local.matching("xqzptrv")).to be_empty
  end

  it "is a no-op for a blank query" do
    expect(Track.local.matching("")).to be_empty
    expect(Track.local.fuzzy("   ")).to be_empty
  end

  it "keeps the generated search_text in step with the row" do
    t = Track.local.find_by(title: "Song 2")
    expect(t.reload.search_text).to include("Song 2", "Blur", "Parklife")
    t.update!(artist: "Gorillaz")
    expect(t.reload.search_text).to include("Gorillaz")
  end
end

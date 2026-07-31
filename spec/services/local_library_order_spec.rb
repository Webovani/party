require "rails_helper"

RSpec.describe LocalLibrary, "album track order" do
  let(:music) { File.expand_path(PartyConfig[:music_dir].to_s) }

  def track(file, title)
    create(:track, :local, artist: "ABBA", album: "Arrival", title: title,
           local_path: "#{music}/ABBA/Arrival/#{file}")
  end

  it "orders by path, so numbered filenames give real album order" do
    track("03 - Dum Dum Diddle.mp3", "Dum Dum Diddle")
    track("01 - When I Kissed the Teacher.mp3", "When I Kissed the Teacher")
    track("02 - Dancing Queen.mp3", "Dancing Queen")

    expect(described_class.new.album_tracks("ABBA", "Arrival").map(&:title))
      .to eq(["When I Kissed the Teacher", "Dancing Queen", "Dum Dum Diddle"])
  end

  it "no longer sorts alphabetically by title" do
    track("01 - Zebra.mp3", "Zebra")
    track("02 - Apple.mp3", "Apple")

    expect(described_class.new.album_tracks("ABBA", "Arrival").map(&:title)).to eq(%w[Zebra Apple])
  end

  it "applies to the untitled-album bucket too" do
    create(:track, :local, artist: "ABBA", album: nil, title: "B", local_path: "#{music}/x/02.mp3")
    create(:track, :local, artist: "ABBA", album: "",  title: "A", local_path: "#{music}/x/01.mp3")

    expect(described_class.new.album_tracks("ABBA", nil).map(&:title)).to eq(%w[A B])
  end
end

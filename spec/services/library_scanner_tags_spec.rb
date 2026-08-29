require "rails_helper"
require "tmpdir"

# wahwah 1.6.7 raises on files ffprobe reads fine - see LibraryScanner#read_tags.
RSpec.describe LibraryScanner, "tag reading" do
  def ffmpeg_available? = system("ffmpeg", "-version", out: File::NULL, err: File::NULL)

  around do |example|
    skip "ffmpeg not installed" unless ffmpeg_available?

    Dir.mktmpdir("scanner-tags") do |dir|
      @path = File.join(dir, "track.mp3")
      system("ffmpeg", "-loglevel", "quiet", "-f", "lavfi", "-i", "sine=frequency=440:duration=1",
             "-metadata", "title=A Tagged Song", "-metadata", "artist=The Artist",
             "-metadata", "album=The Album", @path, exception: true)
      @scanner = described_class.new(music_dir: dir)
      example.run
    end
  end

  it "falls back to ffprobe when the tag library raises" do
    allow(WahWah).to receive(:open).and_raise(IndexError, "index 3 outside of array bounds: -3...3")

    tags = @scanner.send(:read_tags, @path)

    expect(tags[:title]).to eq("A Tagged Song")
    expect(tags[:artist]).to eq("The Artist")
    expect(tags[:album]).to eq("The Album")
    expect(tags[:duration_ms]).to be_within(100).of(1000)
  end

  it "falls back when the tag library succeeds but learned nothing" do
    allow(WahWah).to receive(:open).and_return(
      instance_double(WahWah::Mp3Tag, title: nil, artist: nil, album: nil, duration: nil)
    )

    expect(@scanner.send(:read_tags, @path)[:title]).to eq("A Tagged Song")
  end

  it "does not shell out when the tag library reads the file" do
    expect(Open3).not_to receive(:capture2)

    expect(@scanner.send(:read_tags, @path)[:title]).to eq("A Tagged Song")
  end

  it "still names a track after its file when nothing can read it" do
    allow(WahWah).to receive(:open).and_raise(IndexError)
    allow(Open3).to receive(:capture2).and_return([ "", instance_double(Process::Status, success?: false) ])

    track = Track.new(source: "local", source_uid: @path)
    @scanner.send(:apply_tags, track, @path)

    expect(track.title).to eq("track")
    expect(track.duration_ms).to be_nil
  end
end

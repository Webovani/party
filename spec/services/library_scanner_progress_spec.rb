require "rails_helper"
require "tmpdir"

RSpec.describe LibraryScanner, "progress reporting" do
  around do |example|
    Dir.mktmpdir("scanner-progress") do |dir|
      @dir = dir
      3.times { |i| File.binwrite(File.join(dir, "track#{i}.mp3"), "\0" * 64) }
      File.binwrite(File.join(dir, "cover.jpg"), "\0" * 64)
      example.run
    end
  end

  def events_for(dir)
    events = []
    progress = ->(phase, scanned:, total:, upserted:, path:) {
      events << { phase:, scanned:, total:, upserted:, path: }
    }
    [ described_class.new(music_dir: dir, progress: progress).call, events ]
  end

  it "counts the files while listing them, before any is scanned" do
    _result, events = events_for(@dir)

    expect(events.select { it[:phase] == :listing }.map { it[:total] }).to all(be_nil)

    listed = events.select { it[:phase] == :listed }
    expect(listed.size).to eq(1)
    expect(listed.last).to include(scanned: 3, total: 3)   # the .jpg is not an audio file
    expect(events.index { it[:phase] == :scanning }).to be > events.index { it[:phase] == :listed }
  end

  it "reports the file being scanned against the known total" do
    stub_const("#{described_class}::PROGRESS_INTERVAL", 0)   # otherwise 3 files fit in one tick
    result, events = events_for(@dir)

    scanning = events.select { it[:phase] == :scanning }
    expect(scanning.map { it[:scanned] }).to eq([ 1, 2, 3 ])
    expect(scanning.map { it[:total] }.uniq).to eq([ 3 ])
    expect(scanning.map { it[:path] }).to all(start_with(@dir))
    expect(scanning.map { it[:path] }.uniq.size).to eq(3)
    expect(scanning.last[:upserted]).to eq(result.upserted)
    expect(events.last[:phase]).to eq(:pruning)
  end

  it "throttles the ticks but always fires a final one" do
    _result, events = events_for(@dir)   # three tiny files land inside one interval

    scanning = events.select { it[:phase] == :scanning }
    expect(scanning.size).to eq(1)
    expect(scanning.last).to include(scanned: 3, total: 3)
    expect(scanning.last[:path]).to end_with(".mp3")
  end

  it "scans exactly the same without a progress callback" do
    expect { described_class.new(music_dir: @dir).call }.not_to raise_error
  end
end

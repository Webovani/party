require "rails_helper"
require "csv"

RSpec.describe HistoryExport do
  def rows(csv) = CSV.parse(csv, headers: true)

  it "exports plays and skips, oldest first, and nothing still in the queue" do
    create(:queue_item, state: "queued", track: create(:track, title: "Waiting"))
    old = create(:queue_item, state: "played", queued_by: "ann",
                 track: create(:track, title: "First"))
    new = create(:queue_item, state: "skipped", queued_by: "bob",
                 track: create(:track, title: "Second"))
    old.update_column(:updated_at, 2.hours.ago)
    new.update_column(:updated_at, 1.hour.ago)

    parsed = rows(described_class.new.to_csv)

    expect(parsed.map { it["title"] }).to eq([ "First", "Second" ])
    expect(parsed.map { it["state"] }).to eq([ "played", "skipped" ])
    expect(parsed.map { it["queued_by"] }).to eq([ "ann", "bob" ])
  end

  it "writes the duration both ways and links a YouTube track to its video" do
    create(:queue_item, state: "played",
           track: create(:track, :youtube, source_uid: "abc123", duration_ms: 214_000))

    row = rows(described_class.new.to_csv).first

    expect(row["duration"]).to eq("3:34")
    expect(row["duration_ms"]).to eq("214000")
    expect(row["link"]).to eq("https://www.youtube.com/watch?v=abc123")
  end

  it "links a local track to its file, and keeps it with no library configured" do
    allow(PartyConfig).to receive(:music_dir).and_return(nil)
    track = create(:track, :local)
    create(:queue_item, state: "played", track: track)

    expect(rows(described_class.new.to_csv).first["link"]).to eq(track.local_path)
  end

  it "reports how long a skipped track actually ran" do
    item = create(:queue_item, state: "skipped")
    item.update_columns(started_at: Time.zone.local(2026, 8, 29, 21, 0, 0),
                        updated_at: Time.zone.local(2026, 8, 29, 21, 0, 43))

    row = rows(described_class.new.to_csv).first

    expect(row["started_at"]).to eq("2026-08-29 21:00:00")
    expect(row["played_ms"]).to eq("43000")
  end

  it "leaves played_ms blank for rows that played before started_at existed" do
    create(:queue_item, state: "played")

    row = rows(described_class.new.to_csv).first

    expect(row["started_at"]).to be_nil
    expect(row["played_ms"]).to be_nil
  end

  it "timestamps when the item left the player and when it was added" do
    item = create(:queue_item, state: "played")
    item.update_column(:updated_at, Time.zone.local(2026, 8, 29, 21, 4, 11))

    row = rows(described_class.new.to_csv).first

    expect(row["ended_at"]).to eq("2026-08-29 21:04:11")
    expect(row["added_at"]).to eq(item.created_at.in_time_zone.strftime("%Y-%m-%d %H:%M:%S"))
  end

  it "names the file after the moment of export" do
    expect(described_class.filename(Time.zone.local(2026, 8, 29, 21, 4)))
      .to eq("party-history-20260829-2104.csv")
  end
end

require "rails_helper"

RSpec.describe CacheYoutubeTrackJob, type: :job do
  let(:track) { create(:track, source: "youtube", cache_status: "none", cache_attempts: 0) }
  let!(:item) { create(:queue_item, track: track, state: "queued") }

  before do
    allow(PlayerCommands).to receive(:notify).and_return(true)
    allow(PartyBroadcaster).to receive(:reload)
    # No file on disk, and the download always fails.
    downloader = instance_double(YoutubeDownloader, cached_file: nil)
    allow(downloader).to receive(:download).and_raise(YoutubeDownloader::Error, "nope")
    allow(YoutubeDownloader).to receive(:new).and_return(downloader)
  end

  it "records the failure but keeps the track queued on the first failure" do
    described_class.perform_now(track.id)

    expect(track.reload.cache_attempts).to eq(1)
    expect(track.cache_status).to eq("error")
    expect(QueueItem.exists?(item.id)).to be(true)
  end

  it "removes the track from the queue after the second failure" do
    described_class.perform_now(track.id) # 1st
    expect { described_class.perform_now(track.id) }.to change { QueueItem.exists?(item.id) }.from(true).to(false)

    expect(track.reload.cache_attempts).to eq(2)
    expect(PlayerCommands).to have_received(:notify).with("queue_changed", any_args).at_least(:once)
  end

  it "gives a re-added track a fresh download budget" do
    2.times { described_class.perform_now(track.id) } # track dropped, attempts = 2
    allow(PlayerCommands).to receive(:notify).and_return(true)

    Enqueuer.new("dj").enqueue(track.to_search_result)

    expect(track.reload.cache_attempts).to eq(0)
    expect(track.cache_status).to eq("none")
  end
end

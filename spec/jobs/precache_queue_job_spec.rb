require "rails_helper"

RSpec.describe PrecacheQueueJob, type: :job do
  before { allow(PlayerCommands).to receive(:notify).and_return(true) }

  it "enqueues a cache job for every un-cached queued YouTube track (eager)" do
    5.times { |i| create(:queue_item, track: create(:track, source: "youtube", source_uid: "v#{i}", cache_status: "none")) }

    expect { described_class.perform_now }
      .to have_enqueued_job(CacheYoutubeTrackJob).exactly(5).times
  end

  it "skips pending and local tracks, caching only the un-cached youtube one" do
    create(:queue_item, track: create(:track, source: "youtube", source_uid: "p1", cache_status: "pending"))
    create(:queue_item, track: create(:track, :local))
    uncached = create(:queue_item, track: create(:track, source: "youtube", source_uid: "n1", cache_status: "none"))

    # Exactly one cache job, and it's for the un-cached track (pending/local skipped).
    expect { described_class.perform_now }
      .to have_enqueued_job(CacheYoutubeTrackJob).with(uncached.track.id).once
    expect { described_class.perform_now }
      .to have_enqueued_job(CacheYoutubeTrackJob).once
  end
end

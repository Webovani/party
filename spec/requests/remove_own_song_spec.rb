require "rails_helper"

RSpec.describe "Removing your own song", type: :request do
  before { allow(PlayerCommands).to receive(:notify).and_return(true) }

  def sign_in(nick) = post(session_path, params: { nick: nick })

  it "lets you remove a song you queued" do
    item = create(:queue_item, queued_by: "dj", track: create(:track, :local))
    sign_in "dj"

    expect { delete queue_item_path(item) }.to change(QueueItem, :count).by(-1)
  end

  it "refuses to remove someone else's song" do
    item = create(:queue_item, queued_by: "alice", track: create(:track, :local))
    sign_in "bob"

    expect { delete queue_item_path(item) }.not_to change(QueueItem, :count)
    expect(response.body).to include("not your song")
  end

  it "refuses to remove the song that's playing" do
    item = create(:queue_item, queued_by: "dj", track: create(:track, :local), state: "playing")
    sign_in "dj"

    expect { delete queue_item_path(item) }.not_to change(QueueItem, :count)
    expect(response.body).to include("already playing")
  end

  # Per-viewer markup — why the queue frame is fetched, not broadcast.
  it "shows the remove button only on your own rows" do
    create(:queue_item, queued_by: "dj", track: create(:track, :local, title: "Mine"))
    create(:queue_item, queued_by: "alice", track: create(:track, :local, title: "Theirs"))
    sign_in "dj"

    get queue_region_path
    rows = response.body.scan(%r{<li class="qitem".*?</li>}m)
    mine  = rows.find { |r| r.include?("Mine") }
    other = rows.find { |r| r.include?("Theirs") }
    expect(mine).to include("Remove your song")
    expect(other).not_to include("Remove your song")
  end
end

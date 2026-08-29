require "rails_helper"

# PartyConfig.admin_nick is the only privileged thing in the app: it may drag the
# progress bar and skip a track alone, for unsticking silence when nobody else is
# around to vote.
RSpec.describe "The admin nick", type: :request do
  let(:item) { create(:queue_item, queued_by: "dj", track: create(:track)) }

  before do
    allow(PartyConfig).to receive(:admin_nick).and_return("dj")
    PlayerState.instance.update!(status: "playing", current_queue_item_id: item.id)
  end

  def sign_in(nick) = post(session_path, params: { nick: nick })

  describe "seeking" do
    it "is allowed for the admin nick" do
      sign_in "dj"
      expect(PlayerCommands).to receive(:seek).with("42")

      post player_seek_path, params: { seconds: "42" }
    end

    it "is ignored for anyone else" do
      sign_in "guest"
      expect(PlayerCommands).not_to receive(:seek)

      post player_seek_path, params: { seconds: "42" }
    end

    it "is ignored when no admin nick is configured" do
      allow(PartyConfig).to receive(:admin_nick).and_return(nil)
      sign_in "dj"
      expect(PlayerCommands).not_to receive(:seek)

      post player_seek_path, params: { seconds: "42" }
    end
  end

  describe "skipping" do
    it "skips on the admin's own vote, below the threshold" do
      sign_in "dj"
      expect(PlayerCommands).to receive(:skip)

      post skip_votes_path

      expect(item.skip_vote_count).to be < PartyConfig[:votes_to_skip].to_i
    end

    it "still takes the full count from everyone else" do
      sign_in "guest"
      expect(PlayerCommands).not_to receive(:skip)

      post skip_votes_path
    end

    it "matches the nick case-insensitively" do
      sign_in "DJ"
      expect(PlayerCommands).to receive(:skip)

      post skip_votes_path
    end
  end
end

class SkipVotesController < ApplicationController
  before_action :require_nick

  def create
    item = PlayerState.instance.current_queue_item
    return head(:no_content) unless item

    SkipVote.find_or_create_by(queue_item: item, nick: current_nick)

    # The admin nick skips on its own vote — the way out of a track that is
    # stuck or silent when there is nobody else around to vote with.
    PlayerCommands.skip if admin? || item.skip_vote_count >= PartyConfig[:votes_to_skip].to_i

    # Reaches the voter too — no separate per-actor render.
    PartyBroadcaster.player_changed
    head :no_content
  end
end

class SkipVotesController < ApplicationController
  before_action :require_nick

  def create
    item = PlayerState.instance.current_queue_item
    return head(:no_content) unless item

    SkipVote.find_or_create_by(queue_item: item, nick: current_nick)

    PlayerCommands.skip if item.skip_vote_count >= PartyConfig[:votes_to_skip].to_i
    PartyBroadcaster.refresh # other clients

    # Update the voter's own now-playing (their own morph broadcast is suppressed).
    player = PlayerState.instance
    render turbo_stream: turbo_stream.update(
      "now-playing", partial: "party/now_playing",
      locals: { player: player, current_item: player.current_queue_item,
                votes_to_skip: PartyConfig[:votes_to_skip].to_i }
    )
  end
end

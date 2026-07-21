class PartyController < ApplicationController
  def index
    User.touch_nick(current_nick) if signed_in?
    @player = PlayerState.instance
    @current_item = @player.current_queue_item
    @queue = QueueItem.waiting
    @votes_to_skip = PartyConfig[:votes_to_skip].to_i
  end
end

class QueueItemsController < ApplicationController
  before_action :require_nick

  def create
    result = enqueue_params
    Enqueuer.new(current_nick).enqueue(result) # notifies player + reloads every queue frame
    render turbo_stream: toast_stream("Added “#{result[:title]}” to the queue.")
  rescue Enqueuer::Rejected => e
    render turbo_stream: toast_stream(e.message, type: :alert)
  end

  # You may only pull your own song. Everything is trusted on the LAN, but this
  # stops a mis-tap on someone else's row from silently deleting their pick.
  def destroy
    item = QueueItem.find(params[:id])
    return render(turbo_stream: toast_stream("That's not your song.", type: :alert)) unless item.queued_by == current_nick
    return render(turbo_stream: toast_stream("That one's already playing.", type: :alert)) unless item.state.in?(%w[queued promoted])

    item.destroy
    after_change
  end

  def move_to_front
    return unless current_user.can_move?

    item = QueueItem.find(params[:id])
    # Promoting sends it to the head, and the player parks on an unready head
    # instead of skipping it (player_daemon, wait_for_cache) — so promoting a
    # track that is still downloading stalls playback until the download lands.
    unless item.track.playable?
      return render(turbo_stream: toast_stream("Not ready yet — still downloading or being measured.", type: :alert))
    end

    item.move_to_front!
    current_user.moved!
    after_change
  end

  private

  def enqueue_params
    params.permit(:source, :source_uid, :title, :artist, :album, :duration_ms, :thumbnail_url, :local_path).to_h.symbolize_keys
  end

  # No per-actor render: the reload broadcast reaches this client too.
  def after_change
    PlayerCommands.queue_changed
    PartyBroadcaster.queue_changed
    head :no_content
  end

  def toast_stream(message, type: :notice)
    turbo_stream.append("toasts", partial: "shared/toast", locals: { message: message, type: type })
  end
end

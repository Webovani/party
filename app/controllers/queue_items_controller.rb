class QueueItemsController < ApplicationController
  before_action :require_nick

  def create
    result = enqueue_params
    Enqueuer.new(current_nick).enqueue(result) # notifies player + broadcasts to others
    render turbo_stream: [toast_stream("Added “#{result[:title]}” to the queue."), queue_stream]
  rescue Enqueuer::Rejected => e
    render turbo_stream: toast_stream(e.message, type: :alert)
  end

  def move_to_front
    if current_user.can_move?
      QueueItem.find(params[:id]).move_to_front!
      current_user.moved!
      after_change
    end
  end

  def add_album
    bulk_add(LocalLibrary.new.album_tracks(params[:artist], params[:album]), "album")
  end

  def add_folder
    bulk_add(LocalLibrary.new.folder_tracks(params[:path]), "folder")
  end

  private

  def bulk_add(scope, label)
    result = Enqueuer.new(current_nick).enqueue_all(scope)
    message =
      if result.added.zero?
        "Nothing added — already queued or the queue is full."
      elsif result.skipped.zero?
        "Added #{result.added} #{"track".pluralize(result.added)} from the #{label}."
      else
        "Added #{result.added} (#{result.skipped} skipped — queue limit or duplicates)."
      end
    render turbo_stream: [toast_stream(message, type: result.added.zero? ? :alert : :notice), queue_stream]
  rescue Enqueuer::Rejected => e
    render turbo_stream: toast_stream(e.message, type: :alert)
  end

  def enqueue_params
    params.permit(:source, :source_uid, :title, :artist, :album, :duration_ms, :thumbnail_url, :local_path).to_h.symbolize_keys
  end

  # Update the actor's queue directly (Turbo suppresses a client's own morph
  # broadcast), and notify the player + other clients.
  def after_change
    PlayerCommands.queue_changed
    PartyBroadcaster.refresh
    render turbo_stream: queue_stream
  end

  def queue_stream
    turbo_stream.update("queue", partial: "party/queue", locals: { queue: QueueItem.waiting })
  end

  def toast_stream(message, type: :notice)
    turbo_stream.append("toasts", partial: "shared/toast", locals: { message: message, type: type })
  end
end

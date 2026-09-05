class PlayerController < ApplicationController
  before_action :require_nick

  def play   = run_command { PlayerCommands.play }
  def pause  = run_command { PlayerCommands.pause }
  def skip   = run_command { PlayerCommands.skip }
  def volume = run_command { PlayerCommands.set_volume(params[:volume]) }

  # Admin only. 403, not a silent no-op — the bar is clickable for everyone.
  def seek
    return head(:forbidden) unless admin?

    run_command { PlayerCommands.seek(params[:seconds]) }
  end

  private

  # The daemon applies the command and broadcasts a frame reload, so there is
  # nothing to render back to the actor. Don't rename this `dispatch` — that is
  # an ActionController::Metal method.
  def run_command
    yield
    head :no_content
  end
end

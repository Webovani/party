class PlayerController < ApplicationController
  before_action :require_nick

  def play   = run_command { PlayerCommands.play }
  def pause  = run_command { PlayerCommands.pause }
  def skip   = run_command { PlayerCommands.skip }
  def volume = run_command { PlayerCommands.set_volume(params[:volume]) }
  def seek   = run_command { PlayerCommands.seek(params[:seconds]) if current_nick == "Rhitu" }

  private

  # Commands are applied by the player daemon, which broadcasts the resulting
  # state. Nothing to render back to the actor. (Note: do not name this
  # `dispatch` — that is a framework method on ActionController::Metal.)
  def run_command
    yield
    head :no_content
  end
end

require "json"
require "securerandom"

# Rails controllers and jobs use this to send commands to the player daemon over
# PostgreSQL LISTEN/NOTIFY. The daemon holds the matching LISTEN (see PlayerDaemon).
module PlayerCommands
  CHANNEL = "party_player".freeze
  ACTIONS = %w[play pause stop skip set_volume seek queue_changed].freeze

  module_function

  def play          = notify("play")
  def pause         = notify("pause")
  def stop          = notify("stop")
  def skip          = notify("skip")
  def queue_changed = notify("queue_changed")
  def set_volume(v) = notify("set_volume", volume: v.to_i)
  def seek(seconds) = notify("seek", seconds: seconds.to_f)

  # Send a NOTIFY with a small JSON payload on the primary connection.
  def notify(action, **payload)
    raise ArgumentError, "unknown action #{action}" unless ACTIONS.include?(action)

    # PostgreSQL collapses notifications with identical payloads that are pending
    # at the same time. A nonce keeps every command distinct so none are dropped.
    json = JSON.generate({ action: action, nonce: SecureRandom.hex(4) }.merge(payload))
    quoted = ActiveRecord::Base.connection.quote(json)
    ActiveRecord::Base.connection.execute("NOTIFY #{CHANNEL}, #{quoted}")
    true
  end
end

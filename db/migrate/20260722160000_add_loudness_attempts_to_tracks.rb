class AddLoudnessAttemptsToTracks < ActiveRecord::Migration[8.1]
  # A track is never played unmeasured, so a track ffmpeg can't measure would park
  # the queue head forever. Counted like cache_attempts so it can be given up on.
  def change
    add_column :tracks, :loudness_attempts, :integer, default: 0, null: false
  end
end

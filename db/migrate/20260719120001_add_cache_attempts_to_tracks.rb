class AddCacheAttemptsToTracks < ActiveRecord::Migration[8.1]
  def change
    add_column :tracks, :cache_attempts, :integer, null: false, default: 0
  end
end

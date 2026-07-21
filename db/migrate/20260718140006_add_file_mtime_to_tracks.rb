class AddFileMtimeToTracks < ActiveRecord::Migration[8.1]
  def change
    add_column :tracks, :file_mtime, :datetime
  end
end

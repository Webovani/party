class AddLoudnessToTracks < ActiveRecord::Migration[8.1]
  def change
    # Integrated loudness (EBU R128, LUFS), measured by us rather than read from
    # tags — the library's ReplayGain tags disagree with reality and YouTube
    # downloads have none. Null = not measured yet.
    add_column :tracks, :loudness_lufs, :float
  end
end

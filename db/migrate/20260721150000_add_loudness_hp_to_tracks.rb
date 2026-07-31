class AddLoudnessHpToTracks < ActiveRecord::Migration[8.1]
  def change
    # Integrated loudness of the same file with the bass rolled off. The gap
    # between this and loudness_lufs is how much of the track's level lives in
    # the sub-bass, which K-weighting barely discounts but ears/speakers do.
    add_column :tracks, :loudness_lufs_hp, :float
  end
end

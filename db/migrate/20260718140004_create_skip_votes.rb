class CreateSkipVotes < ActiveRecord::Migration[8.1]
  def change
    create_table :skip_votes do |t|
      t.references :queue_item, null: false, foreign_key: true
      t.string :nick, null: false
      t.timestamps
    end

    add_index :skip_votes, %i[queue_item_id nick], unique: true
  end
end

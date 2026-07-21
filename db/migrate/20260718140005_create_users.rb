class CreateUsers < ActiveRecord::Migration[8.1]
  def change
    create_table :users do |t|
      t.string   :nick, null: false
      t.datetime :last_seen_at
      t.timestamps
    end

    add_index :users, :nick, unique: true
  end
end

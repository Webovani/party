class User < ApplicationRecord
  validates :nick, presence: true, uniqueness: true

  NICK_FORMAT = /\A[\p{Word} .\-]{1,32}\z/

  # Record presence for a nick, creating the row on first sight.
  def self.touch_nick(nick)
    nick = nick.to_s.strip
    return nil if nick.blank?

    user = find_or_create_by!(nick: nick)
    user.update_column(:last_seen_at, Time.current)
    user
  end

  def can_move?
    moved_at.nil? || (moved_at + 30.minutes < Time.current)
  end

  def moved!
    update!(moved_at: Time.current)
  end
end

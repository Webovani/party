class SkipVote < ApplicationRecord
  belongs_to :queue_item

  validates :nick, presence: true, uniqueness: { scope: :queue_item_id }
end

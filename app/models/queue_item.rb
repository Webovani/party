class QueueItem < ApplicationRecord
  STATES = %w[queued promoted playing played skipped].freeze

  belongs_to :track
  has_many :skip_votes, dependent: :destroy

  validates :queued_by, presence: true
  validates :state, inclusion: { in: STATES }

  before_validation :assign_position, on: :create

  # Re-deal the queue once per transaction rather than once per row, so a bulk add
  # (an album/folder) pays for a single pass instead of one per track.
  after_create   :request_reorder
  before_commit  :reorder_if_requested
  after_rollback :forget_reorder_request

  scope :playing, -> { where(state: ['playing']) }
  scope :queued, ->  { where(state: ['queued']).order(:position) }
  scope :waiting, -> { where(state: ['queued', 'promoted']).order(:position) }
  scope :active,  -> { where(state: ['queued', 'promoted', 'playing']).order(:position) }

  # Whether a re-deal is pending for the current transaction (thread-local, so it
  # is scoped to the connection doing the work).
  def self.reorder_requested
    Thread.current[:party_queue_reorder_requested]
  end

  def self.reorder_requested=(value)
    Thread.current[:party_queue_reorder_requested] = value
  end

  def self.reorder!(list = active.to_a)
    return if list.empty?

    transaction do
      deal!(list)
    end
  end

  def self.deal!(list)
    position = list.first.position
    head, tail = list.partition {|i| i.state != "queued" }

    seed = Set.new
    head.each do |i|
      seed.delete(i.queued_by) if i.state != "queued"
      seed << i.queued_by
    end
    tail.each do |i|
      seed << i.queued_by
    end

    chunk = seed.to_a
    head.each do |i|
      chunk.delete(i.queued_by)
      i.update!(position: position)
      position += 1
    end

    while tail.any?
      chunk = seed.to_a if chunk.empty?
      while chosen_nick = chunk.shift
        if chosen_item = tail.find { |i| i.queued_by == chosen_nick }
          tail.delete(chosen_item)
          chosen_item.update!(position: position)
          position += 1
        else
          seed.delete(chosen_nick)
        end
      end
    end
  end

  # The next track that should start.
  def self.head = waiting.first

  # Randomize the queue while keeping the round-robin structure: permute the
  # position values among the (non-promoted) queued items. Then fix fairness
  # with reorder!.
  def self.reshuffle!
    fixed, rest = active.partition { |i| i.state != "queued" }
    return if rest.empty?

    position = rest.first.position

    rest = rest.shuffle
    rest.each do |i|
      i.position = position
      position += 1
    end

    reorder!(fixed + rest)
  end

  # Pending items a nick still has waiting in the queue (for fair-use limits).
  def self.pending_count_for(nick)
    active.where(queued_by: nick).count
  end

  # Is this exact track already waiting/playing?
  def self.track_already_active?(track)
    active.where(track_id: track.id).exists?
  end

  # Promote this item to play next. The most recent promoted item wins the
  # next slot, pushing any earlier promotions behind it.
  def move_to_front!
    return unless state.in?(%w[promoted queued])

    playing, rest = QueueItem.active.partition { |i| i.state == "playing" }
    position = rest.first.position

    self.state = "promoted"
    rest.delete(self)
    rest = [self] + rest
    rest.each do |i|
      i.position = position
      position += 1
    end

    QueueItem.reorder!(playing + rest)
  end

  def skip_vote_count = skip_votes.count

  private

  def request_reorder
    self.class.reorder_requested = true
  end

  # Runs inside the transaction, just before it commits. The first record to get
  # here clears the flag and re-deals, so the rest of a bulk insert are no-ops.
  def reorder_if_requested
    return unless self.class.reorder_requested

    self.class.reorder_requested = false
    self.class.reorder!
  end

  def forget_reorder_request
    self.class.reorder_requested = false
  end

  def assign_position
    self.position ||= (QueueItem.maximum(:position) || 0) + 1
  end
end

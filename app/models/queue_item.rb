class QueueItem < ApplicationRecord
  STATES = %w[queued promoted playing played skipped].freeze

  # Mirrors config/party.yml; fetched with a default so a process older than the
  # config file degrades instead of raising.
  FILLER_MIN_DURATION_MS = 12 * 60 * 1000

  belongs_to :track
  has_many :skip_votes, dependent: :destroy

  validates :queued_by, presence: true
  validates :state, inclusion: { in: STATES }

  before_validation :assign_position, on: :create
  before_validation :flag_filler, on: :create

  # Re-deal the queue once per transaction rather than once per row, so a
  # multi-row write pays for a single pass instead of one per track.
  after_create   :request_reorder
  # Removals change a nick's share of the queue, so re-deal: covers a guest
  # pulling their own song and an undownloadable YouTube track being dropped
  # (CacheYoutubeTrackJob). destroy_all coalesces into one re-deal the same way.
  after_destroy  :request_reorder
  before_commit  :reorder_if_requested
  after_rollback :forget_reorder_request

  scope :playing, -> { where(state: ['playing']) }
  scope :queued, ->  { where(state: ['queued']).order(:position) }
  # Filler sorts behind everything, so `head` only reaches one when nothing else
  # is waiting. Ordering by the column (not just by dealt position) keeps that
  # true even for a row that arrived after the last re-deal.
  scope :waiting, -> { where(state: ['queued', 'promoted']).order(:filler, :position) }
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
      fillers, normal = list.partition(&:filler?)
      deal!(normal) if normal.any?
      park_fillers!(fillers, normal)
    end
  end

  # Filler never joins the round-robin: it is what plays when nobody else wants
  # the slot, so it must not consume a nick's turn or be interleaved. It sits
  # after every normal item, keeping its own relative order.
  def self.park_fillers!(fillers, normal)
    return if fillers.empty?

    position = (normal.filter_map(&:position).max || 0) + 1
    fillers.sort_by { |i| [i.position || 0, i.id] }.each do |item|
      item.update!(position: position)
      position += 1
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

  # Long tracks (a mix) are demoted automatically — see filler_min_duration_ms.
  # Decided once, at add time, so changing the threshold later doesn't reshuffle
  # a queue people are already looking at.
  def flag_filler
    minimum = PartyConfig.fetch(:filler_min_duration_ms, FILLER_MIN_DURATION_MS).to_i
    self.filler = track&.duration_ms.to_i >= minimum
    true
  end

  def assign_position
    self.position ||= (QueueItem.maximum(:position) || 0) + 1
  end
end

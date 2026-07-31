# Splits an alphabetically ordered browse listing into "A–K" style pages, so a
# library with thousands of artists/albums doesn't render as one multi-megabyte
# page on someone's phone.
#
# Ranges are derived from the actual distribution rather than fixed, so they stay
# balanced as the library grows and no page is created that isn't needed: a list
# already under the limit is returned whole, with no pages at all.
class AlphaPager
  LIMIT = 1000

  Page = Struct.new(:key, :label, :entries, keyword_init: true) do
    def count = entries.size
  end

  def initialize(entries, limit: LIMIT)
    @entries = entries
    @limit = limit
  end

  def paged? = @entries.size > @limit

  def pages = @pages ||= paged? ? build : []

  # The requested page, or the first one. Nil when the list needs no paging —
  # callers treat that as "show everything".
  def page_for(key)
    return nil unless paged?

    pages.find { |p| p.key == key.to_s.downcase } || pages.first
  end

  private

  # Accumulate whole initials into a page until the next one would overflow the
  # limit. An initial too big to fit on its own (M holds 1128 albums here) is
  # split again by second letter into "Ma–Me" ranges, so the limit actually holds
  # instead of being quietly exceeded by one page.
  def build
    groups = @entries.group_by { |entry| initial(entry.label) }
    pages = []
    pending = []

    flush = lambda do
      return if pending.empty?

      pages << page(pending.dup, pending.flat_map { |k| groups[k] })
      pending.clear
    end

    groups.keys.sort.each do |key|
      group = groups[key]
      if group.size > @limit
        flush.call
        pages.concat(subdivide(group))
      else
        flush.call if pending.any? && pending.sum { |k| groups[k].size } + group.size > @limit
        pending << key
      end
    end
    flush.call

    pages
  end

  def subdivide(entries)
    groups = entries.group_by { |entry| initial_pair(entry.label) }
    chunk(groups).map { |keys| page(keys, keys.flat_map { |k| groups[k] }) }
  end

  # Greedily pack ordered groups into runs that each stay within the limit.
  def chunk(groups)
    runs = []
    current = []

    groups.keys.sort.each do |key|
      if current.any? && current.sum { |k| groups[k].size } + groups[key].size > @limit
        runs << current
        current = []
      end
      current << key
    end
    runs << current if current.any?

    runs
  end

  def page(keys, entries)
    single = keys.first == keys.last
    Page.new(
      key: (single ? keys.first : "#{keys.first}-#{keys.last}").downcase,
      label: single ? keys.first : "#{keys.first}–#{keys.last}",
      entries: entries
    )
  end

  # Transliterated so a Czech library files Č under C rather than dumping every
  # accented name into "#".
  def initial(label)
    char = ActiveSupport::Inflector.transliterate(label.to_s).to_s[0].to_s.upcase
    char.match?(/[A-Z]/) ? char : "#"
  end

  # "Ma", "Mi" — used only when one initial is too large to be a page by itself.
  # Sorts correctly against its own parent ("M" < "Ma").
  def initial_pair(label)
    first = initial(label)
    return first if first == "#"

    second = ActiveSupport::Inflector.transliterate(label.to_s).to_s[1].to_s.downcase
    second.match?(/[a-z0-9]/) ? "#{first}#{second}" : first
  end
end

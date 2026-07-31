require "rails_helper"

RSpec.describe AlphaPager do
  Item = Struct.new(:label) unless defined?(Item)
  def items(*labels) = labels.map { |l| Item.new(l) }

  it "does not page a list that fits" do
    pager = described_class.new(items("Abba", "Blur"), limit: 10)
    expect(pager).not_to be_paged
    expect(pager.pages).to be_empty
    expect(pager.page_for("a")).to be_nil
  end

  it "splits into ranges that each stay within the limit" do
    entries = ("a".."z").flat_map { |c| items(*Array.new(3) { |i| "#{c}#{i}" }) }
    pages = described_class.new(entries, limit: 10).pages

    expect(pages.map(&:count)).to all(be <= 10)
    expect(pages.sum(&:count)).to eq(78)
    expect(pages.first.label).to match(/\A[A-Z]–[A-Z]\z/)
  end

  # A letter that fits the limit but cannot share a page with its neighbour is
  # labelled plainly, not as a one-element range.
  it "labels and keys a single-letter page without a range" do
    entries = items(*Array.new(8) { |i| "A#{i}" }) + items(*Array.new(8) { |i| "B#{i}" })
    pages = described_class.new(entries, limit: 10).pages

    expect(pages.map(&:label)).to eq(%w[A B])
    expect(pages.map(&:key)).to eq(%w[a b])
  end

  # One letter can hold more than the limit on its own (M has 1128 albums in the
  # real library), so it is split again by second letter rather than shipped as an
  # oversized page.
  it "subdivides an initial that overflows on its own" do
    entries = %w[a e i o u].flat_map { |c| items(*Array.new(6) { |i| "S#{c}#{i}" }) } + items("T1")
    pages = described_class.new(entries, limit: 10).pages

    expect(pages.map(&:count)).to all(be <= 10)
    expect(pages.map(&:label)).to include(a_string_matching(/\ASa?–?S?[a-z]?\z/))
    expect(pages.map(&:label).join).to match(/S[aeiou]/)
    expect(pages.sum(&:count)).to eq(31)
  end

  it "keeps every page within the limit even with a lumpy distribution" do
    entries = items(*Array.new(50) { |i| "M#{("a".."z").to_a[i % 26]}#{i}" }) +
              items(*Array.new(5) { |i| "Z#{i}" })
    pages = described_class.new(entries, limit: 10).pages

    expect(pages.map(&:count)).to all(be <= 10)
    expect(pages.sum(&:count)).to eq(55)
  end

  it "files accented initials under their plain letter" do
    entries = items("Čechomor", "Cabaret", "Zoo") + items(*Array.new(10) { |i| "M#{i}" })
    pages = described_class.new(entries, limit: 5).pages

    c_page = pages.find { |p| p.entries.any? { |e| e.label == "Čechomor" } }
    expect(c_page.entries.map(&:label)).to include("Cabaret")
    expect(pages.none? { |p| p.label.include?("#") }).to be true
  end

  it "falls back to the first page for an unknown key" do
    entries = items(*Array.new(30) { |i| ("a".."z").to_a[i % 26] + i.to_s })
    pager = described_class.new(entries, limit: 10)
    expect(pager.page_for("zzz")).to eq(pager.pages.first)
  end
end

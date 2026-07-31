require "rails_helper"

# Artists / Albums / Folders search their COLLECTIONS as well as the songs inside
# them; All searches songs only, across the whole local library.
RSpec.describe "Library browse modes", type: :request do
  before do
    post session_path, params: { nick: "dj" }
    music = File.expand_path(PartyConfig[:music_dir].to_s)
    create(:track, :local, artist: "ABBA", album: "Arrival", title: "Mamma Mia",
           local_path: "#{music}/Pop/ABBA/Arrival/01.mp3")
    create(:track, :local, artist: "ABBA", album: "Voulez-Vous", title: "Chiquitita",
           local_path: "#{music}/Pop/ABBA/Voulez-Vous/01.mp3")
    create(:track, :local, artist: "Blur", album: "Parklife", title: "Girls & Boys",
           local_path: "#{music}/Rock/Blur/Parklife/01.mp3")
  end

  def frame_get(path) = get(path, headers: { "Turbo-Frame" => "search_results" })
  def headings(body) = body.scan(%r{<h3 class="source-head">\s*([^<\n]*?)\s*\n?\s*</h3>}).flatten

  describe "browsing" do
    it "lists every album across artists in Albums mode" do
      frame_get "/library?browse=albums"
      expect(response.body).to include("Arrival", "Voulez-Vous", "Parklife")
      # each album row is labelled with its artist
      expect(response.body).to include('class="browse-sub">ABBA')
    end

    it "offers all four modes, with the current one active" do
      frame_get "/library?browse=albums"
      expect(response.body.scan(/class="mode[^"]*"[^>]*>([^<]+)/).flatten)
        .to eq(%w[All Artists Albums Folders])
      expect(response.body).to match(/class="mode active"[^>]*>Albums/)
    end

    it "does not list 22k rows in All mode" do
      frame_get "/library?browse=all"
      expect(response.body).not_to include("Mamma Mia")
      # no listing and no hint — the placeholder alone says what a search covers
      expect(response.body).not_to include("Type to search")
    end
  end

  describe "searching a collection" do
    it "finds artists and their songs" do
      frame_get "/search?q=abba&browse=artists"
      expect(headings(response.body)).to eq(%w[Artists Songs])
      expect(response.body).to include("Mamma Mia")     # song
      expect(response.body).to include("artist=ABBA&amp;browse=artists") # artist row
    end

    it "finds albums by album title" do
      frame_get "/search?q=parklife&browse=albums"
      expect(headings(response.body)).to include("Albums")
      expect(response.body).to include("Parklife")
    end

    it "finds albums by their ARTIST, not just their title" do
      frame_get "/search?q=abba&browse=albums"
      expect(response.body).to include("Arrival", "Voulez-Vous")
      expect(response.body).not_to include("Parklife")
    end

    it "finds folders under the current folder, and songs in them" do
      frame_get "/search?q=abba&browse=folders&path=Pop"
      expect(headings(response.body)).to eq(%w[Folders Songs])
      expect(response.body).to include("browse=folders&amp;path=Pop%2FABBA")
    end

    it "does not leak folders from outside the current folder" do
      frame_get "/search?q=blur&browse=folders&path=Pop"
      expect(response.body).not_to match(%r{browse=folders&amp;path=Rock})
    end

    it "searches songs only in All mode" do
      frame_get "/search?q=abba&browse=all"
      expect(headings(response.body)).to eq(["Songs"])
      expect(response.body).to include("Mamma Mia", "Chiquitita")
    end
  end
end

RSpec.describe "Mode row survives a search", type: :request do
  before do
    post session_path, params: { nick: "dj" }
    create(:track, :local, artist: "ABBA", album: "Arrival", title: "Mamma Mia")
  end

  def frame_get(path) = get(path, headers: { "Turbo-Frame" => "search_results" })
  def modes(body) = body.scan(/class="mode[^"]*"[^>]*>([^<]+)/).flatten

  it "still shows all four modes while searching inside one" do
    frame_get "/search?q=abba&browse=albums"
    expect(modes(response.body)).to eq(%w[All Artists Albums Folders])
    expect(response.body).to match(/class="mode active"[^>]*>Albums/)
  end

  it "carries the query when switching mode mid-search, instead of dropping it" do
    frame_get "/search?q=abba&browse=albums"
    expect(response.body).to include("/search?browse=artists&amp;q=abba")
  end

  it "links plainly to the listing when there is no query" do
    frame_get "/library?browse=albums"
    expect(response.body).to include("/library?browse=artists")
    expect(response.body).not_to include("q=")
  end

  it "shows no mode row outside the library" do
    frame_get "/history"
    expect(modes(response.body)).to be_empty
  end

  it "shows no mode row on an unscoped search" do
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([])
    frame_get "/search?q=abba"
    expect(modes(response.body)).to be_empty
  end
end

RSpec.describe "Library lands on All", type: :request do
  before do
    post session_path, params: { nick: "dj" }
    create(:track, :local, artist: "ABBA", title: "Mamma Mia")
  end

  def frame_get(path) = get(path, headers: { "Turbo-Frame" => "search_results" })
  def active(body) = body[/class="mode active"[^>]*>([^<]+)/, 1]

  it "defaults a bare /library to All rather than a 3.5k artist list" do
    frame_get "/library"
    expect(active(response.body)).to eq("All")
    expect(response.body).not_to include("Mamma Mia")
  end

  it "points the Library tab at All" do
    get root_path
    expect(response.body).to include("/library?browse=all")
  end

  it "still honours an explicit mode" do
    frame_get "/library?browse=artists"
    expect(active(response.body)).to eq("Artists")
    expect(response.body).to include("ABBA")
  end
end

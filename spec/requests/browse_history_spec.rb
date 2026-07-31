require "rails_helper"

# Browse state lives in the URL so back/forward work. The same URL must therefore
# answer twice: as a bare frame for in-app navigation, and as the whole app for a
# deep link, a reload, a history restore, or a Turbo morph refresh (which
# re-fetches whatever URL the browser is currently on).
RSpec.describe "Browsing is reflected in the URL", type: :request do
  before { post session_path, params: { nick: "dj" } }

  def frame_get(path) = get(path, headers: { "Turbo-Frame" => "search_results" })

  shared_examples "answers both ways" do |path|
    it "renders the whole app on a full-page visit to #{path}" do
      get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('class="app"')      # shell
      expect(response.body).to include('id="queue"')       # queue still rendered
      expect(response.body).to include('id="search_results"')
    end

    it "renders only the frame for an in-app visit to #{path}" do
      frame_get path
      expect(response).to have_http_status(:ok)
      expect(response.body).to include('id="search_results"')
      expect(response.body).not_to include('class="app"')
    end
  end

  include_examples "answers both ways", "/library?browse=artists"
  include_examples "answers both ways", "/library?browse=folders"
  include_examples "answers both ways", "/history"

  it "renders search results inline on a deep link" do
    create(:track, :local, title: "Dancing Queen", artist: "ABBA")
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([])
    get "/search?q=abba"

    expect(response.body).to include('class="app"')
    expect(response.body).to include("Dancing Queen")
    # the search box agrees with the URL it was reached by
    expect(response.body).to include('value="abba"')
    expect(response.body).to include('data-scope-query-value="abba"')
  end

  it "advances the URL from the frame, and does not pin it as permanent" do
    get root_path
    expect(response.body).to include('<turbo-frame id="search_results" data-turbo-action="advance">')
    # data-turbo-permanent here would survive history navigation and defeat the point
    expect(response.body).not_to match(/id="search_results"[^>]*data-turbo-permanent/)
  end

  it "keeps a browse listing after a re-render of the same URL (morph refresh)" do
    create(:track, :local, artist: "ABBA", album: "Arrival", title: "Mamma Mia")

    2.times do
      get "/library?browse=artists&artist=ABBA"
      expect(response.body).to include("Arrival")
    end
  end

  it "sends an emptied unscoped search home rather than leaving /search?q= in history" do
    frame_get "/search?q="
    expect(response).to redirect_to(root_path)
  end

  it "returns to the browse view when an emptied search was scoped" do
    frame_get "/search?q=&browse=artists&artist=ABBA"
    expect(response).to redirect_to(library_path(browse: "artists", artist: "ABBA"))
  end

  # The All-mode placeholder carries the library size, which used to sit in a
  # separate "Type to search all N songs" hint that duplicated it.
  it "puts the library count in the All placeholder" do
    create_list(:track, 3, :local)
    get "/library?browse=all"
    expect(response.body).to include(%(placeholder="Search all 3 songs in library…"))
  end
end

# Scope state used to live inside a data-turbo-permanent container and be toggled
# only by JS. A permanent element is carried forward and never re-rendered, so it
# went stale after a back-navigation. Everything derived now renders server-side:
# the tabs live inside the frame, the hidden fields render from the URL.
RSpec.describe "Browse state is server-rendered, not synced", type: :request do
  before { post session_path, params: { nick: "dj" } }

  def active_tabs(body) = body.scan(/class="tab[^"]*active[^"]*"[^>]*>([^<]*)/).flatten

  it "marks home active at the root, with no scope fields" do
    get root_path
    expect(active_tabs(response.body)).to eq(["\u2302"])
    expect(response.body).to match(%r{<div id="search-scope-fields">\s*</div>})
  end

  it "marks library active while browsing, and carries the scope as hidden fields" do
    get "/library?browse=artists&artist=ABBA"
    expect(active_tabs(response.body)).to eq(["Library"])
    expect(response.body).to include('name="browse" value="artists"')
    expect(response.body).to include('name="artist" value="ABBA"')
  end

  it "marks history active on history, which has no browse param of its own" do
    get history_path
    expect(active_tabs(response.body)).to eq(["History"])
    expect(response.body).to include('name="browse" value="history"')
  end

  it "keeps an unscoped search on home" do
    allow_any_instance_of(Sources::Youtube).to receive(:search).and_return([])
    get "/search?q=abba"
    expect(active_tabs(response.body)).to eq(["\u2302"])
  end

  it "renders the tabs inside the frame so navigation refreshes them" do
    get "/history", headers: { "Turbo-Frame" => "search_results" }
    expect(response.body).to include('class="tabs"')
    expect(active_tabs(response.body)).to eq(["History"])
  end

  it "only makes the search input permanent" do
    get "/library?browse=artists"
    expect(response.body).to include('id="search-input-wrap" data-turbo-permanent')
    expect(response.body).not_to match(/id="search-controls"[^>]*data-turbo-permanent/)
    expect(response.body).not_to include("search-scope-chip")
  end
end

RSpec.describe "Search placeholder follows the state", type: :request do
  before { post session_path, params: { nick: "dj" } }

  {
    "/"                                   => "Search your local library and YouTube…",
    "/library?browse=artists"             => "Search artists and their songs…",
    "/library?browse=albums"              => "Search albums and their songs…",
    "/library?browse=folders"             => "Search folders and their songs…",
    "/library?browse=artists&artist=ABBA" => "Search in ABBA…",
    "/history"                            => "Search played history…"
  }.each do |path, expected|
    it "says #{expected.inspect} at #{path}" do
      get path
      expect(response.body).to include(%(placeholder="#{expected}"))
      # the frame hands the same text to the scope controller, since frame
      # navigation never re-renders the (permanent) input
      expect(response.body).to include(%(data-scope-placeholder-value="#{expected}"))
    end
  end
end

RSpec.describe "Search history entries", type: :request do
  before { post session_path, params: { nick: "dj" } }

  # The action is flipped per submission by search_controller; "advance" is the
  # starting point, so entering a search from a listing keeps the listing behind it.
  it "defaults the search form to advance, not replace" do
    get root_path
    expect(response.body).to match(/id="search-form"[^>]*data-turbo-action="advance"/)
  end

  it "still sends a cleared scoped search back to its listing" do
    get "/search?q=&browse=artists&artist=ABBA", headers: { "Turbo-Frame" => "search_results" }
    expect(response).to redirect_to(library_path(browse: "artists", artist: "ABBA"))
  end
end

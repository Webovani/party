require "rails_helper"

RSpec.describe "Search by YouTube URL", type: :request do
  before do
    post session_path, params: { nick: "dj" }
    stub_request(:get, /youtube\.com\/oembed/)
      .to_return(status: 200, body: { title: "Some Song", author_name: "Some Artist" }.to_json,
                 headers: { "Content-Type" => "application/json" })
  end

  it "shows the pasted video as a single addable result (no live search)" do
    get search_path(q: "https://youtu.be/dQw4w9WgXcQ"), headers: { "Turbo-Frame" => "search_results" }

    expect(response.body).to include("Some Song")
    expect(response.body).to include("dQw4w9WgXcQ")           # hidden add-to-queue field
    expect(a_request(:post, /youtubei\/v1\/search/)).not_to have_been_made
  end
end

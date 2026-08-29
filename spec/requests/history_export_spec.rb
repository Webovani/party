require "rails_helper"

RSpec.describe "History export", type: :request do
  it "serves a CSV download to a signed-in guest" do
    post session_path, params: { nick: "dj" }
    create(:queue_item, state: "played", queued_by: "dj",
           track: create(:track, title: "Played Once"))

    get history_export_path

    expect(response.media_type).to eq("text/csv")
    expect(response.headers["Content-Disposition"]).to match(/attachment.*party-history-\d{8}-\d{4}\.csv/)
    expect(response.body).to include("Played Once")
  end

  it "is offered on the history listing, outside the Turbo frame" do
    post session_path, params: { nick: "dj" }
    create(:queue_item, state: "played", track: create(:track))

    get history_path

    link = response.body[/<a[^>]*href="#{Regexp.escape(history_export_path)}"[^>]*>/] ||
           response.body[/<a[^>]*class="export-link"[^>]*>/]

    expect(link).to be_present
    expect(link).to include('data-turbo="false"')   # a frame cannot hold a download
  end

  it "needs a nickname like the rest of the app" do
    get history_export_path

    expect(response).to redirect_to(root_path)
  end
end

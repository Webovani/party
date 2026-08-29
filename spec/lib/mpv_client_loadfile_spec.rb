require "rails_helper"

# mpv 0.38 changed the loadfile signature; the old form fails on newer mpv.
RSpec.describe MpvClient, "#loadfile" do
  let(:client) { described_class.new("/tmp/nope.sock") }

  before do
    allow(client).to receive(:command).and_return(nil)
    allow(client).to receive(:get_property).and_return(nil)
  end

  def with_version(version)
    allow(client).to receive(:get_property).with("mpv-version").and_return(version)
  end

  it "passes the index argument on mpv 0.38 and newer" do
    with_version("mpv v0.40.0")

    client.loadfile("/a.webm", start_seconds: 67.8425)

    expect(client).to have_received(:command).with("loadfile", "/a.webm", "replace", -1, "start=67.843")
  end

  it "omits it on older mpv, which has no index argument" do
    with_version("mpv 0.34.1")

    client.loadfile("/a.webm", start_seconds: 5)

    expect(client).to have_received(:command).with("loadfile", "/a.webm", "replace", "start=5.0")
  end

  it "assumes the newer form when the version cannot be read" do
    allow(client).to receive(:get_property).and_raise(described_class::Error, "no socket")

    client.loadfile("/a.webm", start_seconds: 5)

    expect(client).to have_received(:command).with("loadfile", "/a.webm", "replace", -1, "start=5.0")
  end

  it "asks mpv for its version once" do
    with_version("mpv v0.40.0")

    2.times { client.loadfile("/a.webm", start_seconds: 5) }

    expect(client).to have_received(:get_property).once
  end

  it "sends no options at all from the start of a file" do
    client.loadfile("/a.webm")

    expect(client).to have_received(:command).with("loadfile", "/a.webm", "replace")
    expect(client).not_to have_received(:get_property)
  end
end

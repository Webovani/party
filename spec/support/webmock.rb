require "webmock/rspec"

# Block real HTTP in tests; each spec stubs what it needs.
WebMock.disable_net_connect!(allow_localhost: true)

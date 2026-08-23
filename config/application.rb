require_relative "boot"

require "rails"
# Pick the frameworks you want:
require "active_model/railtie"
require "active_job/railtie"
require "active_record/railtie"
require "active_storage/engine"
require "action_controller/railtie"
require "action_mailer/railtie"
require "action_mailbox/engine"
require "action_text/engine"
require "action_view/railtie"
require "action_cable/engine"
# require "rails/test_unit/railtie"

# Require the gems listed in Gemfile, including any gems
# you've limited to :test, :development, or :production.
Bundler.require(*Rails.groups)

module Party
  class Application < Rails::Application
    # Initialize configuration defaults for originally generated Rails version.
    config.load_defaults 8.1

    # Please, add to the `ignore` list any other `lib` subdirectories that do
    # not contain `.rb` files, or that should not be reloaded or eager loaded.
    # Common ones are `templates`, `generators`, or `middleware`, for example.
    config.autoload_lib(ignore: %w[assets tasks])

    # Configuration for the application, engines, and railties goes here.
    #
    # These settings can be overridden in specific environments using the files
    # in config/environments, which are processed later.
    #
    # config.time_zone = "Central Time (US & Canada)"
    # config.eager_load_paths << Rails.root.join("extras")

    # Don't generate system test files.
    config.generators.system_tests = nil

    # --- LAN access ---
    # Only outside test: appending to config.hosts flips host-authorization into
    # allowlist mode, which would block the www.example.com host request specs use.
    unless Rails.env.test?
      require "ipaddr"

      # Private-range IPs, so reaching the box by its LAN address just works.
      config.hosts << IPAddr.new("10.0.0.0/8")
      config.hosts << IPAddr.new("172.16.0.0/12")
      config.hosts << IPAddr.new("192.168.0.0/16")
      # Loopback. Development seeds these itself; production starts from an EMPTY
      # host list, so appending anything above turns on allowlist mode and every
      # localhost request 403s — including a container healthcheck curling /up,
      # and any browser on the host itself.
      config.hosts << "localhost"
      config.hosts << IPAddr.new("127.0.0.0/8")
      config.hosts << IPAddr.new("::1")

      # Health checks must never depend on the allowlist: whatever probes /up
      # (Docker, a load balancer, uptime monitoring) has no reason to know which
      # Host header this deployment answers to.
      config.host_authorization = { exclude: ->(request) { request.path == "/up" } }

      # Any name you reach the app by that is not a private IP — a hostname
      # behind nginx, an mDNS .local — goes here, comma-separated. "*" turns host
      # checking off entirely, which is only sane because this app is LAN-only
      # by design.
      extra_hosts = ENV.fetch("PARTY_HOSTS", "").split(",").map(&:strip).reject(&:empty?)
      wildcard = extra_hosts.delete("*")
      if wildcard
        config.hosts.clear
      else
        config.hosts.concat(extra_hosts)
      end

      # ActionCable (Turbo Stream broadcasts) checks the Origin separately, and a
      # rejected WebSocket looks like "live updates just stopped" rather than an
      # error — so every host allowed above is allowed as an origin too, and
      # PARTY_HOSTS is the single knob for both.
      config.action_cable.allowed_request_origins = [
        %r{https?://localhost(:\d+)?},
        %r{https?://127\.\d+\.\d+\.\d+(:\d+)?},
        %r{https?://\[?::1\]?(:\d+)?},
        %r{https?://192\.168\.\d+\.\d+(:\d+)?},
        %r{https?://10\.\d+\.\d+\.\d+(:\d+)?},
        %r{https?://172\.(1[6-9]|2\d|3[01])\.\d+\.\d+(:\d+)?}
      ]
      config.action_cable.allowed_request_origins +=
        extra_hosts.map { |host| %r{https?://#{Regexp.escape(host)}(:\d+)?} }
      config.action_cable.allowed_request_origins +=
        ENV.fetch("PARTY_ALLOWED_ORIGINS", "").split(",").map(&:strip).reject(&:empty?)
      # Host checking off implies "any origin"; otherwise the WebSocket would
      # still be refused for whatever name got you in.
      config.action_cable.disable_request_forgery_protection = true if wildcard
    end
  end
end

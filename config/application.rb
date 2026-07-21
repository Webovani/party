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

    # --- LAN access via party.rhitu.cz (behind nginx) ---
    # Only outside test: appending to config.hosts flips host-authorization into
    # allowlist mode, which would block the www.example.com host request specs use.
    unless Rails.env.test?
      require "ipaddr"

      # Accept the LAN hostname (and private-range IPs) through host authorization.
      # "party" covers nginx's default upstream Host header if it isn't overridden.
      config.hosts << "party"
      config.hosts << "party.rhitu.cz"
      config.hosts << IPAddr.new("10.0.0.0/8")
      config.hosts << IPAddr.new("172.16.0.0/12")
      config.hosts << IPAddr.new("192.168.0.0/16")

      # Allow ActionCable (Turbo Stream broadcasts) from the LAN origins, otherwise
      # the WebSocket is rejected and live updates stop working behind the proxy.
      config.action_cable.allowed_request_origins = [
        %r{https?://party\.rhitu\.cz},
        %r{https?://localhost(:\d+)?},
        %r{https?://192\.168\.\d+\.\d+(:\d+)?}
      ]
    end
  end
end

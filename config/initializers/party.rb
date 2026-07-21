# Load config/party.yml for the current environment into Rails.application.config.party.
# Access it anywhere via PartyConfig (see lib/party_config.rb).
Rails.application.config.party = Rails.application.config_for(:party)

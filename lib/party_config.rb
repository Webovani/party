# Convenience accessor for config/party.yml (loaded in config/initializers/party.rb
# into Rails.application.config.party). Usage: PartyConfig[:music_dir]
module PartyConfig
  module_function

  def all
    Rails.application.config.party
  end

  def [](key)
    all.fetch(key)
  end

  def fetch(key, default = nil)
    all.fetch(key, default)
  end

  # Blank audio_device means "let mpv choose its default device".
  def audio_device
    value = all[:audio_device]
    value.presence
  end

  # Blank music_dir means "there is no local library" — YouTube-only mode. Note
  # this is a *configuration* answer, not a filesystem one: a configured library
  # on an unmounted drive is still enabled (the index stays browsable and the
  # scanner skips), because that is a temporary state, not a decision.
  def music_dir
    all[:music_dir].presence
  end

  def local_library?
    music_dir.present?
  end

  def audio_extensions
    all[:audio_extensions].map { |e| e.to_s.downcase }
  end
end

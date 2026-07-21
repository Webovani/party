FactoryBot.define do
  factory :track do
    sequence(:source_uid) { |n| "vid#{n}" }
    title { "A Song" }
    artist { "An Artist" }
    duration_ms { 210_000 }

    trait :local do
      source { "local" }
      sequence(:source_uid) { |n| "Artist/song#{n}.mp3" }
      local_path { "/media/music/#{source_uid}" }
    end

    trait :youtube do
      source { "youtube" }
      cache_status { "ready" }
      cache_path { "/tmp/youtube_cache/#{source_uid}.m4a" }
    end

    source { "youtube" }
  end

  factory :queue_item do
    association :track
    queued_by { "dj" }
    state { "queued" }
  end

  factory :player_state do
    status { "stopped" }
    volume { 80 }
  end
end

# Party 🎉

A LAN party jukebox. Anyone on the local network opens a mobile-first web page,
sets a nickname, searches music (local library + YouTube), and adds tracks to one
shared queue. Audio plays out of the host machine's speakers via **mpv**. Fair-use
rules stop one person hogging the queue; skip-voting lets the group move on.

## Stack

- **Ruby 3.4 / Rails 8.1**, Hotwire (Turbo + Stimulus), Propshaft, importmap.
- **PostgreSQL** (primary + Solid Queue/Cache/Cable databases).
- **mpv** for playback (JSON IPC), **yt-dlp** for caching YouTube audio.
- **wahwah** (pure Ruby) for reading local audio tags.

## Architecture

Three processes share one PostgreSQL database:

| Process | What it does |
|---|---|
| **web** (Puma) | Serves the mobile UI, search, queue & control endpoints. |
| **player** (`bin/player`) | Owns an mpv child, drives the queue, sole author of `PlayerState`. |
| **jobs** (Solid Queue) | YouTube caching (`yt-dlp`) and local library scanning. |

- Rails/jobs → player commands travel over **PostgreSQL `LISTEN/NOTIFY`**
  (`lib/player_commands.rb` ↔ `PlayerDaemon`).
- Live UI updates use **Turbo 8 page refreshes (morphing)** broadcast to a shared
  `party` stream (`lib/party_broadcaster.rb`). The now-playing progress bar animates
  client-side between refreshes, so we never broadcast per-second ticks.
- **Sources** (`lib/sources/`) are a pluggable registry (`Local`, `Youtube`) kept
  Rails-agnostic so they could be extracted into a gem. YouTube search is a pure-Ruby
  reimplementation of the mopidy_youtube InnerTube hack
  (`lib/sources/youtube/innertube_client.rb`).

## Prerequisites

- PostgreSQL reachable at `localhost:5433` as `dbuser`/`dbpass`
  (override via `PARTY_DB_HOST/PORT/USER/PASSWORD`).
- `mpv`, `yt-dlp`, and `ffmpeg` on `PATH`.
- `foreman` for `bin/dev` (`gem install foreman`).

## Setup

```bash
bundle install
bin/rails db:prepare        # creates primary + cache/queue/cable DBs, loads schema
bin/rails party:scan        # index the local music library (see config below)
```

## Run

```bash
bin/dev                     # starts web + jobs + player (Procfile.dev)
```

Then open `http://<host>:3000` from any device on the LAN. Set a nickname and go.

To run pieces individually:

```bash
bin/rails server -b 0.0.0.0   # web
bin/jobs                      # Solid Queue worker
bin/player                    # mpv player daemon
```

## Configuration

`config/party.yml` (all overridable by env var):

| Key | Env | Default | Notes |
|---|---|---|---|
| `music_dir` | `PARTY_MUSIC_DIR` | `/media/music` | Local library root; degrades gracefully if unmounted. |
| `cache_dir` | `PARTY_CACHE_DIR` | `tmp/youtube_cache` | Where YouTube audio is downloaded. |
| `mpv_ipc_socket` | `PARTY_MPV_SOCKET` | `tmp/party-mpv.sock` | mpv JSON IPC socket. |
| `audio_device` | `PARTY_AUDIO_DEVICE` | (mpv default) | e.g. `alsa/hw:1,0`. |
| `votes_to_skip` | `PARTY_VOTES_TO_SKIP` | `2` | Skip-vote threshold. |
| `max_queue_length` | `PARTY_MAX_QUEUE_LENGTH` | `30` | Total queue cap. |
| `max_queue_per_user` | `PARTY_MAX_QUEUE_PER_USER` | `20` | Per-nick pending cap. |
| `precache_ahead` | `PARTY_PRECACHE_AHEAD` | `3` | Upcoming YouTube tracks kept downloaded. |

## Testing

```bash
bundle exec rspec
```

Covers the InnerTube search parser (fixture-based, no network) and the full queue
flow (nick gate, enqueue, fair-use rules, queue management, skip-vote threshold).

## Notes

- **YouTube caching fallback:** some videos refuse the default yt-dlp client
  ("not available on this app"); the downloader falls back to the Android client.
- **Local library** is re-indexed with `bin/rails party:scan` or the in-app
  "Rescan" button (incremental by file mtime).
- Adding a new source = add `lib/sources/<name>.rb` and register it in
  `Sources::Registry`.

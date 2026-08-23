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

- PostgreSQL. With no configuration the app connects over the local unix socket
  as your OS user; set `PARTY_DB_HOST` / `PARTY_DB_PORT` / `PARTY_DB_USER` /
  `PARTY_DB_PASSWORD` for anything else.
- `mpv`, `yt-dlp`, and `ffmpeg` on `PATH`.
- `foreman` for `bin/dev` (`gem install foreman`).

## Setup

```bash
bundle install
cp .env.example .env        # optional: only if a default needs changing
bin/rails db:prepare        # creates primary + cache/queue/cable DBs, loads schema
```

`.env` is read in development and test as well as by `docker compose`, so one
file configures both. Everything in it has a working default — out of the box the
app runs **YouTube-only**; point `PARTY_MUSIC_DIR` at a music directory and run
`bin/rails party:scan` to switch the local library on.

## Run

Three ways, all running the same three processes:

**Docker** (self-contained: brings its own PostgreSQL, mpv, ffmpeg and yt-dlp) —
see **[docs/DOCKER.md](docs/DOCKER.md)**, which also covers how audio gets out of a
container:

```bash
cp .env.example .env        # set SECRET_KEY_BASE, MUSIC_DIR, PULSE_SOCKET, PUID
docker compose up -d --build
docker compose exec web bin/rails party:scan
```

**systemd user units** — how it actually runs on the party box, on port 3007
behind nginx (`deploy/systemd/`, driven by `bin/party start|stop|restart|logs`).

**Foreground**, for development:

```bash
bin/dev                       # web + jobs + player (Procfile.dev)
bin/rails server -b 0.0.0.0   # or the pieces individually
bin/jobs                      # Solid Queue worker
bin/player                    # mpv player daemon
```

Then open `http://<host>:<port>` from any device on the LAN. Set a nickname and go.

## Configuration

`config/party.yml` (all overridable by env var):

| Key | Env | Default | Notes |
|---|---|---|---|
| `music_dir` | `PARTY_MUSIC_DIR` | *(blank)* | Local library root; degrades gracefully if unmounted. **Blank (the default) = no library at all**: YouTube-only, no Library tab or browsing (see below). |
| `cache_dir` | `PARTY_CACHE_DIR` | `tmp/youtube_cache` | Where YouTube audio is downloaded. Absolute paths are stored in the DB — moving it invalidates the cache. |
| `mpv_ipc_socket` | `PARTY_MPV_SOCKET` | `tmp/party-mpv.sock` | mpv JSON IPC socket. |
| `audio_device` | `PARTY_AUDIO_DEVICE` | (mpv default) | e.g. `alsa/hw:1,0`, `pulse/<sink>`. |
| `audio_filter` | `PARTY_AUDIO_FILTER` | (none) | Extra mpv filter chain; per-track loudness gain is applied separately. |
| `votes_to_skip` | `PARTY_VOTES_TO_SKIP` | `2` | Skip-vote threshold. |
| `max_queue_length` | `PARTY_MAX_QUEUE_LENGTH` | `30` | Total queue cap. |
| `max_queue_per_user` | `PARTY_MAX_QUEUE_PER_USER` | `20` | Per-nick pending cap. |
| `precache_ahead` | `PARTY_PRECACHE_AHEAD` | `3` | Upcoming YouTube tracks kept downloaded. |
| `filler_min_duration_ms` | `PARTY_FILLER_MIN_MS` | `720000` | At/above this length a track is "filler": plays only when nothing else waits. |
| `loudness_target_lufs` | `PARTY_LOUDNESS_TARGET` | `-20` | Every track is measured once (ffmpeg `ebur128`) and played at target − measured. |
| `loudness_max_gain_db` | `PARTY_LOUDNESS_MAX_GAIN` | `0` | Attenuation only — no clipping risk. |
| `loudness_min_gain_db` | `PARTY_LOUDNESS_MIN_GAIN` | `-20` | Floor on the correction. |
| `loudness_bass_correction` | `PARTY_LOUDNESS_BASS_CORRECTION` | `0.5` | How much of the sub-bass share to discount (0 = plain R128). |
| `loudness_highpass_hz` | `PARTY_LOUDNESS_HIGHPASS_HZ` | `200` | Cutoff of the second, highpassed measurement. |
| `show_loudness_debug` | `PARTY_LOUDNESS_DEBUG` | `false` | Per-track LUFS/gain badges in the queue. |

**YouTube-only mode.** Blank `music_dir` switches the local library off
(`PartyConfig.local_library?`): the Library tab and all browse views disappear,
`/library` redirects home, search asks YouTube alone, scanning is a no-op that
prunes nothing, and local tracks left in the database are hidden from history and
refused at add time — an unplayable local file would otherwise park the player on
it forever. A configured library on an unmounted drive is *not* "off"; that is
temporary, and the index stays browsable.

Database connection: `PARTY_DB_HOST` / `PARTY_DB_PORT` / `PARTY_DB_USER` /
`PARTY_DB_PASSWORD` / `PARTY_DB_NAME`. All blank by default, i.e. the local
PostgreSQL over its unix socket as the current OS user.

Host authorization: private-range IPs (10/8, 172.16/12, 192.168/16) and
localhost are always allowed. `PARTY_HOSTS` adds names you reach the box by
(comma-separated) — each one is allowed as a WebSocket origin too, so live
updates work behind a proxy without a second setting; `PARTY_ALLOWED_ORIGINS`
exists for the cases that need one anyway. `PARTY_HOSTS=*` turns host checking
off entirely. **This app has no authentication by design — keep it on the LAN.**

`.env.example` collects all of it in one file for the Docker deployment.

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

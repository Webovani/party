# Party 🎉

A LAN party jukebox. Anyone on the local network opens a mobile-first web page,
sets a nickname, searches music (local library + YouTube), and adds tracks to one
shared queue. Audio plays out of the host machine's speakers via **mpv**. Fair-use
rules stop one person hogging the queue; skip-voting lets the group move on.

## Run it

You need Docker with the Compose plugin (2.24+) and a machine with speakers. The
image brings everything else: PostgreSQL, mpv, ffmpeg, yt-dlp.

```bash
cp .env.example .env          # fill in the four settings below
docker compose up -d --build  # first run also creates the schema
```

| In `.env` | |
|---|---|
| `SECRET_KEY_BASE` | required — `openssl rand -hex 64` |
| `PULSE_SOCKET` | the host's audio socket — `echo $XDG_RUNTIME_DIR/pulse/native` |
| `PUID` / `PGID` | your uid/gid (`id -u`, `id -g`) — must match the socket's owner |
| `MUSIC_DIR` | music library path, or empty to run YouTube-only |

Open `http://<host>:3008` from any device on the LAN, set a nickname, queue
something. With a library, index it once (and after adding music):

```bash
docker compose exec web bin/rails party:scan
```

**[docs/DOCKER.md](docs/DOCKER.md)** covers the rest: getting audio out of a
container (PulseAudio, ALSA, over the network), restarting the player without
cutting a song, backups, and what to do when something does not start.

## Configuration

`config/party.yml`, all overridable by env var — `.env` is where you set them:

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

**Access control.** There is none: no login, no host allowlist, any name or IP that
reaches the port gets in. That is the point at a party, and it is also why the
only real control is where you publish it. `WEB_BIND` in `.env` picks the
interface (blank = all of them, `192.168.1.10` = that LAN address only,
`127.0.0.1` = this machine only); outside Docker it is `bin/rails server -b`.
**Keep it on the LAN.**

## Architecture

- **Ruby 3.4 / Rails 8.1**, Hotwire (Turbo + Stimulus), Propshaft, importmap.
- **PostgreSQL** (primary + Solid Queue/Cache/Cable databases).
- **mpv** for playback (JSON IPC), **yt-dlp** for caching YouTube audio.
- **wahwah** for reading local audio tags, ffmpeg where it gives up.

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
- Adding a source = add `lib/sources/<name>.rb` and register it in `Sources::Registry`.

## Development

Running the three processes on the host instead of in containers needs Ruby 3.4,
PostgreSQL, and `mpv`, `yt-dlp`, `ffmpeg` on `PATH`:

```bash
bundle install
bin/rails db:prepare        # primary + cache/queue/cable DBs, loads schema
bin/dev                     # web + jobs + player (needs foreman)
bundle exec rspec
```

`.env` is read here too (development and test), so one file configures both ways
of running. The database defaults to the local PostgreSQL over its unix socket as
your OS user; `PARTY_DB_HOST` / `PARTY_DB_PORT` / `PARTY_DB_USER` /
`PARTY_DB_PASSWORD` / `PARTY_DB_NAME` change that.

For a permanent install without containers, run the three under whatever
supervisor you already use — systemd user units work well, and the player wants
`KillMode=mixed` with a generous `TimeoutStopSec` so a graceful stop can wait for
the current song to finish.

Two things that surprise people: some videos refuse the default yt-dlp client
("not available on this app") and fall back to the Android one, and `party:scan`
is incremental by file mtime, so a re-tagged file is only re-read once its mtime
moves.

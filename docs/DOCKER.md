# Running Party in Docker

Four containers: `db` (PostgreSQL) plus the same three processes the systemd
units run — `web` (Puma), `jobs` (Solid Queue) and `player` (owns mpv). All three
app roles come from one image, which carries **mpv, ffmpeg and yt-dlp**.

Everything you can tune lives in `.env` (start from `.env.example`).

---

## 1. Prerequisites

- Docker Engine with the Compose plugin (`docker compose version` ≥ 2.24 — the
  ALSA override uses the `!override` tag).
- The music library on a local path.
- Something to play sound through — read **[Audio](#4-audio)** *before* the first
  run; one setting there (`PUID`) is baked into the image at build time.

## 2. Quick start

```bash
cp .env.example .env
```

Edit `.env` — the four that matter:

| Variable | What to put there |
|---|---|
| `SECRET_KEY_BASE` | `openssl rand -hex 64` (or, once the image exists, `docker run --rm party:latest bin/rails secret`) |
| `MUSIC_DIR` | host path of the library, e.g. `/srv/music` — **or leave empty (the default) for [YouTube-only](#25-running-without-a-music-library)** |
| `PULSE_SOCKET` | host audio socket — `echo $XDG_RUNTIME_DIR/pulse/native` |
| `PUID` / `PGID` | **the desktop user's** uid/gid — `id -u` / `id -g` |

Then:

```bash
docker compose up -d --build          # first run also creates the schema
docker compose exec web bin/rails party:scan   # index the library (~22k tracks)
docker compose ps
```

Open `http://<host>:3008` (`WEB_PORT` in `.env`) from any device on the LAN, set a
nickname, queue something.

> The non-Docker deployment uses port **3007** and whatever PostgreSQL is on the
> host; the compose stack avoids both so the two can coexist.
> They cannot share speakers, though — see [§7](#7-coexisting-with-the-systemd-deployment).

## 2.5 Running without a music library

The library is optional. Leave `MUSIC_DIR` empty and the box runs on YouTube
alone:

```bash
MUSIC_DIR=
```

`/music` then resolves to an empty named volume and `PARTY_MUSIC_DIR` goes blank,
which is the actual switch (`PartyConfig.local_library?`). With it off:

- the **Library** tab and every browse view are gone — `/library` redirects home,
  so a shared link or bookmark degrades gracefully rather than 404ing;
- search asks **YouTube only** — the local source is not even registered, so
  there is no empty "Local library" section;
- a `?browse=albums` URL falls back to a plain search instead of silently
  scoping it to a library that isn't there;
- `party:scan` is a no-op that reports why, and **prunes nothing** — the existing
  index survives, so switching the library back on is `MUSIC_DIR=…` plus a scan;
- local tracks still in the database are hidden from history and **refused at add
  time**. That last one matters: a missing local file would park the player on it
  forever, since nothing counts attempts and drops it the way a dead YouTube link
  gets dropped.

It is a configuration decision, not a filesystem one — a configured library on a
drive that happens to be unmounted stays *on* (the index remains browsable, the
scanner skips), because that is temporary.

## 3. What runs where

| Container | Command | Needs |
|---|---|---|
| `db` | postgres 17 | `pgdata` volume |
| `web` | `bin/rails server` | library (ro), cache; runs `db:prepare` on boot |
| `jobs` | `bin/jobs` | yt-dlp (downloads), ffmpeg (loudness), library, cache |
| `player` | `bin/player` | mpv **+ the audio device**, library, cache |

`jobs` and `player` wait for `web` to report healthy, so exactly one process ever
migrates the database.

One image serves all three roles (~1.4 GB: Ruby slim + mpv, ffmpeg, and the
upstream yt-dlp build — the Debian yt-dlp package lags behind YouTube's changes
badly enough to break downloading; pin it with `--build-arg YT_DLP_VERSION=…`).
`config/database.yml` and `config/party.yml` are part of the build context and
had to stop being gitignored for a clean checkout to be buildable; both are
env-driven and hold no secrets.

Two paths are absolute *inside the database* and must stay stable across
restarts: the YouTube cache (`/data/cache`, the `youtube_cache` volume) and each
local track's path (`/music/...`). Changing where either is mounted invalidates
what is already indexed — see [§8](#8-keeping-an-existing-database).

## 4. Audio

**Yes, a container can drive the speakers.** It needs a route to the host's audio,
and there are three, in descending order of "just works".

### a) PulseAudio / PipeWire socket — the default

The host runs a sound server; the container is just another client of it. This is
what `docker-compose.yml` does out of the box:

```yaml
volumes:
  - ${PULSE_SOCKET}:/run/pulse/native
  - ${PULSE_COOKIE}:/run/pulse/cookie:ro
environment:
  PULSE_SERVER: unix:/run/pulse/native
```

**The one rule: `PUID` must equal the uid that owns the socket.** PulseAudio
authenticates unix clients by peer credentials, and `/run/user/<uid>` is mode
0700, so a mismatched uid cannot even reach the socket, let alone connect. The
uid is baked in at build time (`--build-arg PUID`), so change `.env` *before*
`--build`, or rebuild after changing it.

Verify without making a sound — listing devices requires a live connection to the
server, so this failing means the route is broken:

```bash
docker compose exec player mpv --audio-device=help
# List of detected audio devices:
#   'auto' (Autoselect device)
#   'pulse/alsa_output.pci-0000_00_1f.3.analog-stereo' (Built-in Audio Analog Stereo)
#   'alsa' (Default (alsa))
```

A named `pulse/...` entry means the container is talking to the host's sound
server. Only `auto`/`alsa`/`jack`/`sdl` and no `pulse/<sink>` means it is not.

And a one-second 440 Hz beep, when you actually want to hear it:

```bash
docker compose exec player mpv --no-video --length=1 av://lavfi:sine=frequency=440
```

Caveats worth knowing:

- The socket only exists **while that user is logged in** (systemd `user@.service`
  owns `/run/user/<uid>`). On a headless box, `loginctl enable-linger <user>` or
  use ALSA instead.
- If the host's PulseAudio starts *after* the container, the bind mount points at
  a socket that no longer exists — restart `player`.
- PipeWire is fine: `pipewire-pulse` provides the same socket at the same path.

### b) ALSA directly

For a headless box with no sound server. Nothing else may hold the card.

```bash
docker compose -f docker-compose.yml -f docker-compose.alsa.yml up -d
```

That override drops the Pulse mounts and adds `/dev/snd` plus the host's `audio`
group (`AUDIO_GID`, check with `getent group audio`). Then pick a device:

```bash
docker compose -f docker-compose.yml -f docker-compose.alsa.yml exec player \
  mpv --audio-device=help
```

and set e.g. `PARTY_AUDIO_DEVICE=alsa/hw:0,0` in `.env`.

If a desktop session is running, this will fail with "Device or resource busy" —
PulseAudio already owns the card. Use (a), or stop the sound server.

### c) Network audio

Ugly but occasionally the answer — the box with the speakers is not the box with
Docker. Load `module-native-protocol-tcp` on the audio host and point
`PULSE_SERVER` at `tcp:<host>:4713` (mount the cookie, and note that TCP *does*
require it). No local socket, no uid matching. Adds latency; use for testing, not
for the party.

### Not the answer

`--network host` alone does nothing for audio — audio is not a network device.
`--privileged` is not needed either; the only thing missing is access to a socket
or a device node, both of which are granted explicitly above.

## 5. Day-to-day

```bash
docker compose ps
docker compose logs -f player                 # or web / jobs
docker compose exec web bin/rails console
docker compose exec web bin/rails party:scan  # reindex the library
docker compose exec db psql -U party party_production
```

**Restarting the player is the one operation with a rule.** `SIGTERM` means
*finish the current song, then exit*, and `stop_grace_period: 900s` gives it room
to do that:

```bash
docker compose restart player      # graceful — waits for the song to end
docker compose kill player && docker compose up -d player   # immediate, cuts the song
```

Which container to restart after a change:

| Changed | Restart |
|---|---|
| anything in `app/`, `lib/` | rebuild the image (`docker compose up -d --build`) — production mode has no reloading |
| `.env` value used by the web UI | `docker compose up -d web` |
| `.env` value used by playback (audio device/filter, loudness) | `docker compose up -d player` |
| `PUID`/`PGID` | `docker compose up -d --build` (they are build args) |

Backups — the queue, nicks, library index and loudness measurements are all in
Postgres:

```bash
docker compose exec -T db pg_dump -U party party_production > party-backup.sql
```

## 6. Configuration

`.env.example` is the reference: it lists every `PARTY_*` knob with its default
and a note on what it does. The originals live in `config/party.yml`, which reads
the same environment variables, so the containerised and systemd deployments
behave identically.

Two settings exist only for containers:

- `PARTY_HOSTS` — extra `Host` values to accept, for a name you reach the box by.
  Private-range IPs and `localhost` are always allowed, and each name listed here
  is allowed as a WebSocket origin too; `*` turns host checking off entirely
  (also disables the WebSocket origin check — LAN-only deployments only).
- `PARTY_DB_PREPARE` — `auto` (default: the web role prepares the schema),
  `true`, or `false`.

Behind nginx, point the upstream at `localhost:${WEB_PORT}` and put the name you
serve under in `PARTY_HOSTS`. It already proxies `/cable`, which Turbo's live updates
need.

## 7. Coexisting with the systemd deployment

Different ports, different databases, different YouTube cache — but **one set of
speakers**. Two players will happily play at once and it sounds exactly as bad as
it reads. Before starting the compose stack:

```bash
bin/party stop player     # or: bin/party stop all
```

To go the other way permanently, `systemctl --user disable --now party-web
party-jobs party-player`.

## 8. Keeping an existing database

A fresh stack starts empty (rescan the library and you are done — the queue and
nick history are the only things that are not reproducible). To carry the
existing data over, the absolute paths in it have to keep resolving:

```bash
# 1. dump from the host's PostgreSQL
pg_dump party_development > party.sql   # add -h/-p/-U if your PARTY_DB_* say so

# 2. mount the library at the SAME path the old rows refer to — say the old
#    deployment indexed /srv/music. In .env:
#      MUSIC_DIR=/srv/music
#    and add to docker-compose.override.yml for web/jobs/player:
#      volumes:
#        - /srv/music:/srv/music:ro
#      environment:
#        PARTY_MUSIC_DIR: /srv/music

# 3. restore
docker compose up -d db
docker compose exec -T db psql -U party party_production < party.sql
```

Cached YouTube files keep their old `tmp/youtube_cache` paths in `cache_path`; the
simplest fix is to let them re-download (the queue re-caches on demand), or copy
the files into the volume and update the column.

## 9. Troubleshooting

| Symptom | Cause |
|---|---|
| mpv logs `pw.conf … can't load config client.conf` | harmless — mpv's PipeWire output probing for a config the container has no reason to ship |
| `web` unhealthy, log says `SECRET_KEY_BASE` missing | not set in `.env` |
| `player` restarts in a loop, log: `Connection refused` from mpv | audio route broken; run the `--audio-device=help` check in §4 |
| `mpv: could not connect to socket` right after boot | the host's Pulse socket was replaced (relogin); `docker compose up -d player` |
| `web` stays unhealthy, log repeats `Blocked hosts: localhost:3000`, `jobs`/`player` stuck in `Created` | host authorization refusing the healthcheck. Fixed in `config/application.rb` (loopback allowed, `/up` excluded) — if you see it again, something re-narrowed `config.hosts`. Note `jobs` and `player` wait on `web` being **healthy**, so one 403 keeps the whole stack down. |
| Blank page, `Blocked host` in the web log | add the name to `PARTY_HOSTS` |
| Live updates stop, WebSocket 403 | origin not allowed — `PARTY_ALLOWED_ORIGINS` |
| Tracks queue but never play, stuck "waiting" | the daemon parks on an unready head: check `jobs` logs for yt-dlp/ffmpeg failures |
| Library search finds nothing | `party:scan` not run, or `MUSIC_DIR` points somewhere empty |
| No Library tab at all | `MUSIC_DIR` is empty — that is YouTube-only mode (§2.5) |
| YouTube search and downloads both fail | on this network YouTube is blocked at the router — unrelated to Docker |

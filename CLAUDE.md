# Party — LAN jukebox

Shared music queue for a LAN party. Everyone on the network opens the page, sets a nick
(no passwords — all users trusted), searches the local library or YouTube, and adds to one
shared queue. Audio plays out of this machine's speakers via mpv.

`README.md` covers stack/setup/config. **This file covers the things that will bite you.**

---

## Running it — systemd, not `bin/dev`

The README's "Run" section is **stale**: it says `bin/dev` on port 3000. The app now runs as
three **systemd user units** (`party-web`, `party-jobs`, `party-player`) behind nginx at
`party.rhitu.cz` (LAN-only). The web port is **`WEB_PORT` in `.env`** (currently 3008) — the unit
runs `bin/web`, which reads `WEB_PORT`/`WEB_BIND` from there, so it is one setting for both
deployments rather than a hardcoded `-p` that silently outvoted the file.
`bin/dev`/`Procfile.dev` still exist but are legacy.

```bash
bin/party status
bin/party restart player        # graceful — WAITS for the current song to end
bin/party restart player now    # force (SIGKILL); ~3s of silence
bin/party restart jobs          # bounce the worker without touching playback
bin/party logs player           # journalctl -f
```

There is also a **container** deployment (`docker-compose.yml`, guide in `docs/DOCKER.md`):
same three roles from one image, its own PostgreSQL, the same `WEB_PORT`, `RAILS_ENV=production` (so no
code reloading — rebuild). It is an alternative to the systemd stack, not a replacement: they now
share `WEB_PORT` as well as the speakers, so the second one to start fails to bind. Stop one
before starting the other. Audio reaches the player
container through the host's PulseAudio socket, which only works if the image was built with
`PUID` = the socket owner's uid.

`bin/party` sets `XDG_RUNTIME_DIR` itself, so it works from any shell (ssh included).
Units live in `deploy/systemd/`; installed copies are in `~/.config/systemd/user/`. After
editing a unit: copy it there + `systemctl --user daemon-reload`.

**Which process must restart for a change?**

| changed | needs |
|---|---|
| controllers, views, models, `lib/sources` | nothing — web auto-reloads (development env) |
| jobs (`app/jobs/*`) | `bin/party restart jobs` |
| `app/services/player_daemon.rb`, or model code the daemon calls (`QueueItem.head`) | `bin/party restart player` |
| a `deploy/systemd/*.service` | copy to `~/.config/systemd/user/` + `daemon-reload` |

Model changes are the trap: the web picks them up instantly but the player daemon loaded
them at boot, so displayed order and played order can silently disagree until you restart it.

## RVM — always `ruby-3.4.10@party`

This project runs in the **`ruby-3.4.10@party` gemset**, per `.ruby-version` + `.ruby-gemset`
(split in two so rbenv/asdf don't choke on a gemset suffix). Nothing belongs in
the default `ruby-3.4.10` gemset.

**Before any `bundle install` / `gem install`, check `rvm current` says `ruby-3.4.10@party`.**
A non-login shell (or one that started outside this directory) can come up on the *default*
gemset, and then installs land in the wrong place. That is exactly how this repo once ended up
with a duplicate copy of every gem in the default gemset — `bin/dev` auto-installs `foreman` if
missing, and it went to the wrong gemset.

**`rvm gemset empty <name>` ignores the name and empties the *current* gemset.** `rvm --force
gemset empty ruby-3.4.10` run from this directory wiped `@party` instead (125 gems → 64; restored
with `bundle install`). To clean the default gemset, delete its `gems/` by explicit path, after
printing the target and refusing anything containing `@`.

`deploy/party.env` pins that gemset for the systemd units (they get a clean env, so RVM's shell
hooks don't apply). Regenerate it from a shell where `rvm current` == `ruby-3.4.10@party`:

```bash
gembins=$(echo "$GEM_PATH" | tr ':' '\n' | sed 's:$:/bin:' | paste -sd:)
printf 'GEM_HOME=%s\nGEM_PATH=%s\nMY_RUBY_HOME=%s\nRUBY_VERSION=%s\nPATH=%s\n' \
  "$GEM_HOME" "$GEM_PATH" "$MY_RUBY_HOME" "$RUBY_VERSION" \
  "$MY_RUBY_HOME/bin:$gembins:/home/rhitu/.rvm/bin:/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin" \
  > deploy/party.env
```

Verify with a clean-env boot (this is what systemd does):

```bash
set -a; . deploy/party.env; set +a
env -i HOME="$HOME" GEM_HOME="$GEM_HOME" GEM_PATH="$GEM_PATH" \
    MY_RUBY_HOME="$MY_RUBY_HOME" PATH="$PATH" \
    bin/rails runner 'puts Gem.dir'   # must print .../ruby-3.4.10@party
```

## Queue ordering — the intricate part

Live in `QueueItem`. Read `reorder!`/`deal!` before changing anything here; it took many
iterations to land.

**Positions are the source of truth.** `deal!` writes the play order into `position`, so
ordering is just `waiting` (`ORDER BY position`) and `head = waiting.first`. Display order and
played order are therefore identical by construction.

**States:** `queued` (normal), `promoted` ("play next"), `playing`, `played`, `skipped`.
Promotion is a *state*, not a negative position.

**The algorithm** — build a nick rotation ("seed"), then deal the tail by it:

1. **Head** = playing + promoted items. Walk them; per nick *append if new, move-to-last if
   seen*. Most-recently-active nick ends up last.
2. Walk the **tail** (`queued`); append any nick not already in the seed. (Newcomers land at
   the end of the seed.)
3. Each head item **consumes one slot** from the seed — `chunk.delete(nick)`, so **at most one
   per nick**. This is why promoting two songs still only defers you one round.
4. Deal the tail by cycling the remaining chunk, refilling from the full seed when it empties
   (the seed "repeats to infinity"). A nick with nothing left is dropped from the seed.

**Rules that fall out of this (all spec'd in `spec/models/queue_item_fairness_spec.rb`):**
- A newcomer **appends to the current round** — it never jumps the front. It only *appears*
  first when everyone else already took their slot this round.
- Consuming the head only **shifts**; state changes don't re-deal, so the tail is stable.
- Adding **only inserts**; existing relative order is preserved.

**Re-deal timing:** `after_create` **and `after_destroy`** set a thread-local flag; `before_commit`
runs `reorder!` once and clears it. So any transaction touching several rows — a `destroy_all`,
a seed — re-deals **once**, not per row (measured on the album add this replaced: 143 UPDATEs/306 ms
→ 28/45 ms). Don't move this back to a per-row `after_create`.
`before_commit` does fire for destroyed records — that's load-bearing here, and spec'd.

**Removals re-deal** because they change a nick's share. Two paths destroy queue items:
`QueueItemsController#destroy` (a guest pulling their *own* song — checked against `current_nick`,
and refused for the song that's playing) and `CacheYoutubeTrackJob` dropping an undownloadable
video. The latter must use `QueueItem.active` (queued **+ promoted +** playing): the daemon *parks*
on an unready head rather than skipping it (`player_daemon.rb`, `wait_for_cache`), so a promoted
dead video — which is exactly what "play next" on a broken link produces — stalls playback forever
if it isn't removed.

**Filler (long tracks).** A queued track at least `filler_min_duration_ms` (12 min) long is
flagged `filler` at add time — decided once, so moving the threshold never reshuffles a queue
people are looking at. Filler is excluded from `deal!` entirely (it must not consume a nick's
turn) and parked after every normal item by `park_fillers!`; `waiting` orders by `filler, position`
so `head` reaches one only when nothing else waits. The daemon's `interrupt_filler` runs on
`queue_changed`: if a filler is playing and any non-filler is waiting, it saves `time-pos` into
`resume_position_ms`, returns the item to **queued** (not played) and advances. It resumes via
mpv's `loadfile … start=`, NOT a seek after load — loading first plays a moment from 0:00.

`reshuffle!` exists but is **deliberately disabled** (controller action commented out, button
behind `if false`). Leave it off unless asked.

## Player daemon

- **Graceful stop:** SIGTERM = finish the current song, then exit. A second SIGTERM, or SIGINT,
  stops immediately. The unit needs **`KillMode=mixed`** (the default `control-group` would
  SIGTERM mpv directly and cut the song) and **`TimeoutStopSec=900`** (so systemd waits out a
  song instead of SIGKILLing at 15s). Don't "simplify" those away.
- **Reconcile on boot:** an interrupted song that can't be resumed is returned as `promoted`
  (not `queued`) so it keeps its spot at the front.
- Talks to mpv over a JSON IPC socket; the reader thread must never do heavy work (it pushes to
  a queue for a separate dispatcher) or it deadlocks.
- Commands arrive via PostgreSQL `LISTEN/NOTIFY` on channel `party_player`.
- `deploy/restart-at-song-change.sh watch|now|graceful` times a restart to a track boundary and
  reports the audio-silent window. `watch` is read-only and safe.
- **mpv's `volume` property is CUBIC, not linear amplitude.** Measured on 0.34.1:
  `gain_dB = 3 × 20·log₁₀(vol/100)` — volume 50 is −18 dB, not −6 dB. Never fold a gain factor
  into it (doing so applied every loudness correction **three times over in dB**). Per-track gain
  belongs in the audio filter, which takes exact dB. `--volume-gain` would be the clean knob but
  only exists from mpv 0.36.

## Loudness normalisation

Every queued track is measured once and played through a per-track gain. **Never trust tags** —
the library's ReplayGain values disagree with the audio, and YouTube downloads have none.

- `LoudnessAnalyzer` runs ffmpeg `ebur128` over the **whole file**, twice: as-is, and highpassed
  (`loudness_highpass_hz`, 200). Stored as `loudness_lufs` / `loudness_lufs_hp`.
- **Do not pass `-v error` to ffmpeg** — it suppresses the very summary being parsed.
- The gap between the two readings is the sub-bass share. R128's K-weighting barely discounts
  bass, so a psytrance track (≈5 dB of bass) sounds far quieter than mid-forward pop (≈0.7 dB) at
  the same LUFS. `loudness_bass_correction` (0.5) is how much of that gap to correct;
  `Track#effective_loudness_lufs` applies it. Both raw numbers are stored, so **changing the knob
  never requires re-analysing** — only a process restart.
- Gain is clamped to `[-20, 0]`: attenuation only, no clipping risk, amp provides make-up.
- **Nothing plays unmeasured.** `Track#playable?` = `ready_to_play? && loudness_measured?`; the
  daemon parks on a head that fails it (`wait_for_track`), exactly as it does for an uncached
  track, and "play next" is refused for one. Unmeasured means gain 0 — i.e. FULL volume — which
  is the worst possible outcome at the moment we know least. `AnalyzeLoudnessJob` counts
  `loudness_attempts` and drops a track that can't be measured after 2 tries, otherwise an
  unreadable file would park the head forever; it also NOTIFYs the player on success, since the
  daemon is sitting there waiting.
- `Track#loudness_measured?` means *both* passes are present. Rows missing the second one are
  re-measured by the `PrecacheQueueJob` sweep. Guards use that predicate, not `loudness_lufs.nil?`.
- `PartyConfig[]` uses `fetch` and **raises** on an unknown key, and `config/party.yml` is frozen
  into `Rails.application.config.party` at boot. Adding a key and testing with `bin/rails runner`
  (a fresh process) proves nothing about the running web service — it will 500 on every render
  until restarted. Loudness lookups use `PartyConfig.fetch(key, DEFAULT)` for exactly this reason.

## The update path — three self-reloading frames

State reaches clients as a **signal, never as markup**. `PartyBroadcaster` broadcasts one custom
Turbo stream action, `reload_frame` (registered in `app/javascript/stream_actions.js`), and the
client refetches that frame's own `src`:

| frame | `src` | reloads on |
|---|---|---|
| `#queue` | `/party/queue` | `PartyBroadcaster.queue_changed` — add, remove, re-deal, badge |
| `#now-playing` | `/party/now_playing` | `.player_changed` — track, play/pause/stop, seek, skip vote |
| `#player-volume` | `/party/volume` | `.volume_changed` — volume only |

`.track_changed` = player + queue. All served by `PartyController`; the shell renders the frames
**empty** (`_app.html.erb`), so a browse page carries no queue or player markup and costs no queue
query.

**Why a signal and not the HTML.** The markup is per-viewer — whose rows get a ✕, who may promote,
whose skip button says "skip now". One server-rendered copy broadcast to the whole party can never
be right for everybody, so each client renders its own with its own cookies. This is the reason the
obvious `broadcast_replace_to` is wrong here.

**Never reintroduce `broadcast_refresh_to`.** It made every client re-fetch and morph its *whole
current page* on every change: a ±2% volume tap re-rendered everyone's open browse listing (728 KB
on Albums). It hit the actor too — `turbo_stream_refresh_tag` suppresses your own refresh by
matching `Turbo.current_request_id`, and the broadcast comes from the **player daemon**, which has
no request id. That is also why controllers used to return a duplicate `turbo_stream.update` for
the actor; they no longer need to, because a `reload_frame` broadcast reaches the actor like
everyone else.

Four bugs came from that refresh being too broad — the scope chip going stale, scroll jumping to
the top on someone else's add, the toast re-animating, typing wiped mid-search. All four are gone
by construction: **nothing re-renders the page unprompted any more**, so `data-turbo-permanent` is
gone from `#search-input-wrap` and `#toasts`, `search_sync.js` is deleted (its job folded back into
`scope_controller.js`), and the toast deadline hack with it. Before adding a permanent element,
check whether something is broadcasting too broadly instead.

### Other Hotwire gotchas

- The player-bar frames are `display: contents` so `.player-bar`'s grid can lay out rows that live
  in two different frames — the volume has to sit at the right of the controls row, not under it.
- Player POSTs answer `204`; the visible result arrives as the daemon's broadcast. A `button_to`
  inside a frame is fine with that.
- **`volume_controller` debounces the echo, not the post.** Every tap posts immediately; the
  reload of `#player-volume` is held off until 600 ms after the last tap (`holdFrame`). Debouncing
  the post moved the volume late, and since the frame reloads on the echo of your own post, each
  echo tore the controller down and flushed the pending post early — a double-tap read 14, 12, 14.
  The level asked for lives at **module scope** because the trailing reload rebuilds the
  controller; until it echoes back, a differing incoming value is a stale echo and is ignored (at
  most 3 s, in case the post was lost).
- `frame_reloads.js` sits between `reload_frame` and `frame.reload()`: it coalesces a burst of
  signals for one frame into a reload now plus one at the end, and lets a control hold its own
  frame while it is being worked. Deferred, never dropped.
- `progress_controller` resyncs on the **item id**, not on `positionMs`: the daemon persists
  position once a second, so resyncing on it dragged the bar back every time the frame reloaded.
- The `<title>` is rendered twice from `document_title` — into `<head>` for the first paint, and
  into the now-playing frame, which is the only thing that reloads on a track change
  (`page_title_controller`). The head is never re-rendered after load.
- Anything with the `hidden` attribute needs an explicit `.foo[hidden] { display: none }` if the
  class sets `display` — class beats the UA rule and the element stays visible.

## Browsing — URL is the state

The `search_results` frame carries `data-turbo-action="advance"`, so browsing writes itself into
the URL and back/forward/reload/link-sharing all work.

**Every browse URL must answer twice.** `render_frame_or_page` (ApplicationController): a
`turbo_frame_request?` gets the bare frame, anything else gets the whole app shell with that
content already in the frame. The "anything else" is not hypothetical — it's deep links, reloads,
history restores. `library`/`history`/`search` used to redirect to root on a full-page visit; that
breaks the moment the URL starts changing.

`shared/_frame_content` is the single definition of what's inside the frame, rendered by both the
frame responses and the shell, so the two can't drift. The tabs (⌂ / Library / History) live
**inside** the frame for the same reason the chip had to leave the permanent container: in there
they're re-rendered on every navigation and are server-correct with no JS.

`scope_controller.js` only handles what genuinely can't be server-rendered — frame navigation does
not re-render the controls above the frame, so it pushes scope/query/placeholder into them. The
server renders the same values on a full load, so a missed connect degrades to "briefly stale", not
"stuck forever".

**Library modes:** `all` (songs only, no listing — 22k rows is not a browse), `artists`, `albums`
(flat across artists, grouped by `(artist, album)` since titles repeat), `folders`. A scoped search
returns matching **collections and** the songs in them (`LocalLibrary#search_entries`). Folder
search matches **every segment** of a path, not just the directory holding the tracks — an artist
folder like `Pop/ABBA` contains no files of its own and would otherwise never match.

**The library is optional.** Blank `music_dir` ⇒ `PartyConfig.local_library?` is false and the
whole local half switches off: `Sources::Registry` doesn't register `Local`, the Library tab is
not rendered, `/library` redirects home, `current_browse_scope` ignores every non-history
`browse=` param (so a bookmarked scope degrades to a plain search instead of silently scoping to
a library that isn't there), and `LibraryScanner` returns `reason: :disabled` **without pruning**
— turning it back on is one env var plus a scan. Two non-obvious pieces: `Enqueuer#enqueue`
refuses `source: "local"` because a missing local file parks the head forever (nothing counts
attempts for local the way `CacheYoutubeTrackJob` does for YouTube), and `LocalLibrary#music_dir`
**raises** `LocalLibrary::Disabled` rather than returning `File.expand_path("")`, which is the
working directory and would quietly make the app root "the library". "Off" is a config answer,
not a filesystem one — an unmounted drive is still *on*.

**`AlphaPager`** splits the flat listings into `A–K` pills sized from the actual distribution
(≤1000/page; lists under that get no pills). An initial too big on its own is subdivided by second
letter — M alone holds 1128 albums. Initials are transliterated, so Č files under C. Without this,
Albums rendered 4.3 MB in 3.6 s; it is now 738 KB / 0.77 s.

## Sources & caching

- **YouTube search** = the InnerTube `youtubei/v1/search` hack (spoofed WEB client, no API key).
  Pasting a **YouTube URL** resolves that one video via oEmbed instead of searching.
- **Audio** = `yt-dlp` download to `tmp/youtube_cache`. Caching is **eager** — every queued
  YouTube track, not just the next few — so a reshuffle/promotion can't surface an uncached
  track. A track that fails to download **twice** is dropped from the queue (`cache_attempts`).
- Most cached files are 360p **video**+audio (~13 MB) rather than audio-only: YouTube rejects the
  web client, and the android fallback exposes no audio-only stream. Known and accepted; the real
  fix is authenticating with cookies.
- **Local search** uses PG full-text with **prefix matching** (`to_tsquery`, `term:*`), so "abb"
  finds ABBA.

## Testing

```bash
bundle exec rspec          # 132 examples
```

Uses the separate `party_test` DB — safe to run while the live stack is up.

`config/application.rb` clears `config.hosts` and disables the ActionCable origin check in every
env, so request specs' `www.example.com` host is fine. Never *append* to `config.hosts` instead —
appending flips host-authorization into allowlist mode and 403s those specs, the container
healthcheck on `/up`, and whatever name a guest reached the box by.

## Misc

- **Defaults are generic; this box's values live in the gitignored `.env`.** `config/party.yml`
  and `config/database.yml` default to "no music library, local PostgreSQL over its unix socket
  as the OS user" so a fresh clone runs. `.env` (loaded by `dotenv-rails` in development and
  test, *and* by `docker compose`) is what puts this box back on port **5433** as
  `dbuser`/`dbpass` and points `PARTY_MUSIC_DIR` at `/home/rhitu/Music`. Delete a line from
  `.env` and you get the stranger's defaults — including a suddenly library-less app. That is
  not hypothetical: `.env` used to carry a *separate* `MUSIC_DIR` for Docker and leave
  `PARTY_MUSIC_DIR` blank, so the library was on under compose and silently off on the next
  systemd restart. There is now **one** setting; compose remaps it to `/music` itself.
- There is no host allowlist any more: any name or IP that reaches the port gets in. Access is
  controlled by where the app listens — `WEB_BIND` for the container, `bin/rails server -b`
  outside it.
- `PARTY_ADMIN_NICK` (this box: `Rhitu`) is the only privilege in the app: seek, and skip on
  one vote. Nick match only — anyone who types it has it.
- Local library is `/home/rhitu/Music` (~22k tracks). `bin/rails party:scan` to reindex; the
  in-app "Rescan" button was deliberately removed.
- **Never `pgrep -f`/`pkill -f` a pattern that also appears in your own command line** — it
  matches the shell running it and kills your own session. Use the bracket trick (`[b]in/player`)
  or `pgrep -x`.
- The user's stack is usually live during a session. Don't stop/restart services or run anything
  that mutates the live queue without asking; reading logs/DB is fine.

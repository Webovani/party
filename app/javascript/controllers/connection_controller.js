import { Controller } from "@hotwired/stimulus"

// Live updates arrive over ActionCable and are fire-and-forget: while the tab is
// backgrounded the socket drops and any broadcasts are missed. So when the tab
// returns to the foreground (or the network comes back) we reload the live frames
// and show a status badge — but only when the gap was long enough to matter, so
// quick tab-switches stay quiet. Only those frames can be stale; what is being
// browsed changes by navigation alone.
const HEARTBEAT_MS = 10000    // reachability check cadence while visible
const STALE_MS = 15000        // show "Syncing…" only if last success older than this
const RETRY_MS = 3000         // recheck cadence while failing
const FAILS_FOR_OFFLINE = 2   // consecutive failures before showing "Offline"
const LIVE_FRAMES = ["queue", "now-playing", "player-volume"]

export default class extends Controller {
  static targets = ["badge"]

  connect() {
    this.lastSuccess = Date.now() // page just loaded => server was reachable
    this.fails = 0
    this.lastResync = 0

    this.onVisible = () => { if (!document.hidden) this.resync() }
    this.onShow = (e) => { if (e.persisted) this.resync() } // bfcache restore
    this.onOnline = () => this.resync()
    this.onOffline = () => this.check()

    document.addEventListener("visibilitychange", this.onVisible)
    window.addEventListener("pageshow", this.onShow)
    window.addEventListener("online", this.onOnline)
    window.addEventListener("offline", this.onOffline)

    this.heartbeat = setInterval(() => { if (!document.hidden) this.check() }, HEARTBEAT_MS)
    this.setState("live")
  }

  disconnect() {
    document.removeEventListener("visibilitychange", this.onVisible)
    window.removeEventListener("pageshow", this.onShow)
    window.removeEventListener("online", this.onOnline)
    window.removeEventListener("offline", this.onOffline)
    clearInterval(this.heartbeat)
    clearTimeout(this.retryTimer)
  }

  // Foreground / reconnect: catch up missed broadcasts. Only flag "Syncing…" when
  // we've actually been out of touch for a while (otherwise refresh silently).
  resync() {
    const now = Date.now()
    if (now - this.lastResync < 1000) return // ignore rapid duplicate events
    this.lastResync = now

    if (now - this.lastSuccess > STALE_MS) this.setState("syncing")
    for (const id of LIVE_FRAMES) document.getElementById(id)?.reload()
    this.check()
  }

  async check() {
    clearTimeout(this.retryTimer)
    try {
      const res = await fetch("/up", { cache: "no-store" })
      if (res.ok) return this.onSuccess()
    } catch { /* fall through to failure */ }
    this.onFailure()
  }

  onSuccess() {
    this.lastSuccess = Date.now()
    this.fails = 0
    this.setState("live")
  }

  onFailure() {
    this.fails += 1
    if (this.fails >= FAILS_FOR_OFFLINE) this.setState("offline")
    this.retryTimer = setTimeout(() => this.check(), RETRY_MS) // keep probing to auto-recover
  }

  setState(state) {
    if (!this.hasBadgeTarget) return
    const badge = this.badgeTarget
    if (state === "live") {
      badge.hidden = true
      return
    }
    badge.hidden = false
    badge.dataset.state = state
    badge.textContent = state === "offline" ? "Offline — reconnecting…" : "Syncing…"
  }
}

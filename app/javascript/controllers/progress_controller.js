import { Controller } from "@hotwired/stimulus"

// Animates the now-playing progress bar client-side between server refreshes, so
// we never broadcast per-second position ticks. Re-syncs when the broadcast morph
// updates the position/duration/playing values. Click-to-seek posts to the player.
export default class extends Controller {
  static targets = ["bar", "fill", "elapsed"]
  static values = { positionMs: Number, durationMs: Number, playing: Boolean }

  connect() { this.resync() }
  disconnect() { this.stop() }

  positionMsValueChanged() { this.resync() }
  playingValueChanged() { this.resync() }

  resync() {
    this.base = this.positionMsValue
    this.startedAt = performance.now()
    this.stop()
    this.render()
    if (this.playingValue) this.loop()
  }

  loop() {
    this.raf = requestAnimationFrame(() => { this.render(); this.loop() })
  }

  stop() {
    if (this.raf) cancelAnimationFrame(this.raf)
    this.raf = null
  }

  current() {
    if (!this.playingValue) return this.base
    return this.base + (performance.now() - this.startedAt)
  }

  render() {
    const dur = this.durationMsValue
    const pos = dur > 0 ? Math.min(this.current(), dur) : 0
    const pct = dur > 0 ? (pos / dur) * 100 : 0
    if (this.hasFillTarget) this.fillTarget.style.width = `${pct}%`
    if (this.hasElapsedTarget) this.elapsedTarget.textContent = format(pos)
  }

  seekClick(event) {
    if (this.durationMsValue <= 0) return
    const rect = this.barTarget.getBoundingClientRect()
    const ratio = Math.min(Math.max((event.clientX - rect.left) / rect.width, 0), 1)
    const seconds = (this.durationMsValue / 1000) * ratio

    const body = new FormData()
    body.append("seconds", seconds.toFixed(1))
    fetch("/player/seek", {
      method: "POST",
      body,
      headers: { "X-CSRF-Token": csrfToken() }
    })
  }
}

function format(ms) {
  const total = Math.floor(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${String(s).padStart(2, "0")}`
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

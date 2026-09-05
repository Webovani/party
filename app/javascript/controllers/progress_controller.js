import { Controller } from "@hotwired/stimulus"
import { post } from "post"

// Animates the now-playing progress bar client-side between server updates, so we
// never broadcast per-second position ticks. Click-to-seek posts to the player.
export default class extends Controller {
  static targets = ["bar", "fill", "elapsed"]
  static values = { itemId: String, positionMs: Number, durationMs: Number, playing: Boolean, seekUrl: String }

  connect() { this.resync() }
  disconnect() { this.stop() }

  // Resync on the item, not positionMs: the daemon persists position once a
  // second, so that would drag the bar back on every unrelated frame reload.
  itemIdValueChanged() { this.resync() }
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

    post(this.seekUrlValue, { seconds: seconds.toFixed(1) })
  }
}

function format(ms) {
  const total = Math.floor(ms / 1000)
  const m = Math.floor(total / 60)
  const s = total % 60
  return `${m}:${String(s).padStart(2, "0")}`
}

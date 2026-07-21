import { Controller } from "@hotwired/stimulus"

// Volume as a percentage in ±2% steps. Updates the readout immediately and posts
// the new level to the player, debounced so a burst of taps sends one request.
const STEP = 2

export default class extends Controller {
  static targets = ["display"]
  static values = { url: String, level: Number } // mpv volume percent (0–100)

  // Fires on connect and on broadcasts: adopt the player's current level.
  levelValueChanged() {
    this.pct = clamp(this.levelValue)
    this.render()
  }

  up() { this.set(this.pct + STEP) }
  down() { this.set(this.pct - STEP) }

  set(next) {
    this.pct = clamp(next)
    this.render()
    this.post()
  }

  render() {
    if (this.hasDisplayTarget) this.displayTarget.textContent = `${this.pct}%`
  }

  post() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => {
      const body = new FormData()
      body.append("volume", this.pct)
      fetch(this.urlValue, {
        method: "POST",
        body,
        headers: { "X-CSRF-Token": csrfToken() }
      })
    }, 150)
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}

function clamp(v) {
  return Math.max(0, Math.min(100, Math.round(v)))
}

function csrfToken() {
  return document.querySelector('meta[name="csrf-token"]')?.content
}

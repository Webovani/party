import { Controller } from "@hotwired/stimulus"
import { post } from "post"

// Volume as a percentage in ±2% steps. Updates the readout immediately and posts
// the new level to the player, debounced so a burst of taps sends one request.
const STEP = 2

export default class extends Controller {
  static targets = ["display"]
  static values = { url: String, level: Number } // mpv volume percent (0–100)

  // Fires on connect: adopt the player's current level. The daemon's echo reloads
  // this frame and rebuilds the element, so no value swap mid-interaction.
  levelValueChanged() {
    this.pct = clamp(this.levelValue)
    this.render()
  }

  up() { this.set(this.pct + STEP) }
  down() { this.set(this.pct - STEP) }

  set(next) {
    this.pct = clamp(next)
    this.render()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.send(), 150)
  }

  render() {
    if (this.hasDisplayTarget) this.displayTarget.textContent = `${this.pct}%`
  }

  send() {
    this.timer = null
    post(this.urlValue, { volume: this.pct })
  }

  // Flush, don't drop: this frame reloads on anyone's volume change and tears the
  // controller down, so clearing a pending post would swallow the tap.
  disconnect() {
    if (this.timer) {
      clearTimeout(this.timer)
      this.send()
    }
  }
}

function clamp(v) {
  return Math.max(0, Math.min(100, Math.round(v)))
}

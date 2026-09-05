import { Controller } from "@hotwired/stimulus"
import { post } from "post"
import { holdFrame } from "frame_reloads"

// Volume as a percentage in ±2% steps. Every tap posts immediately; what is
// deferred is the echo, since a frame reload mid-burst rebuilds the control and
// drags the readout back through levels already passed.
const STEP = 2
const HOLD_MS = 600 // quiet time after the last tap before the frame may reload
const ECHO_GRACE_MS = 3000

// Module scope: the trailing reload rebuilds this controller, so the level asked
// for has to outlive the instance.
let want = null // null once the player has echoed it back
let wantUntil = 0

export default class extends Controller {
  static targets = ["display"]
  static values = { url: String, level: Number } // mpv volume percent (0–100)

  // Fires on connect: adopt the player's level, unless ours is still in flight -
  // then this is a stale echo and would bounce the readout backwards.
  levelValueChanged() {
    if (want !== null && Date.now() > wantUntil) want = null // post lost; trust the player

    const level = clamp(this.levelValue)
    if (want !== null && level !== want) return this.render(want)

    want = null
    this.render(level)
  }

  connect() { this.render(this.pct) }

  up() { this.set(this.pct + STEP) }
  down() { this.set(this.pct - STEP) }

  set(next) {
    want = clamp(next)
    wantUntil = Date.now() + ECHO_GRACE_MS
    this.render(want)

    const frame = this.element.closest("turbo-frame")
    if (frame) holdFrame(frame.id, HOLD_MS)
    post(this.urlValue, { volume: want })
  }

  render(pct) {
    this.pct = pct
    if (this.hasDisplayTarget) this.displayTarget.textContent = `${pct}%`
  }
}

function clamp(v) {
  return Math.max(0, Math.min(100, Math.round(v)))
}

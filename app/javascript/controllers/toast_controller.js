import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a toast after a timeout; click to dismiss early.
//
// Reconnect-safe on purpose: toasts live in #toasts, which is
// data-turbo-permanent, so a broadcast morph refresh relocates that node and this
// controller disconnects and reconnects. Naively that restarted the timer and
// replayed the CSS animation — the same toast appeared to fire a second time,
// which is what you see when someone adds a song and the daemon broadcasts.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    const deadline = this.element.dataset.toastDeadline

    if (deadline) {
      // Already on screen: keep the original expiry and don't animate again.
      this.element.classList.add("toast-settled")
      this.timer = setTimeout(() => this.dismiss(), Math.max(Number(deadline) - Date.now(), 0))
    } else {
      const timeout = this.timeoutValue || 4000
      this.element.dataset.toastDeadline = String(Date.now() + timeout)
      this.timer = setTimeout(() => this.dismiss(), timeout)
    }
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("toast-out")
    setTimeout(() => this.element.remove(), 250)
  }
}

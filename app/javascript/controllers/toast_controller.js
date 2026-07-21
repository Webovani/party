import { Controller } from "@hotwired/stimulus"

// Auto-dismisses a toast after a timeout; click to dismiss early.
export default class extends Controller {
  static values = { timeout: Number }

  connect() {
    this.timer = setTimeout(() => this.dismiss(), this.timeoutValue || 4000)
  }

  disconnect() {
    clearTimeout(this.timer)
  }

  dismiss() {
    this.element.classList.add("toast-out")
    setTimeout(() => this.element.remove(), 250)
  }
}

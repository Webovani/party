import { Controller } from "@hotwired/stimulus"

// Debounced search: submits the form (which targets the search_results frame)
// a short moment after the user stops typing, and manages the input's clear (✕)
// button. Escaping a browse scope is the home tab, inside the frame.
export default class extends Controller {
  static targets = ["input", "clear"]

  // Long-ish on purpose. Local search answers in ~150ms, but an unscoped query
  // also hits YouTube, which measured ~11s — so every keystroke that slips
  // through starts a request that outlives several more keystrokes.
  static DEBOUNCE_MS = 500

  connect() {
    this.toggleClear()
  }

  submit() {
    this.setHistoryAction()
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), this.constructor.DEBOUNCE_MS)
  }

  // Where the result lands in history:
  //
  //   browsing -> search   advance, so Back returns to what you were browsing
  //   search   -> search   replace, so refining a query doesn't stack one entry
  //                        per keystroke and make Back replay half-typed queries
  //   search   -> cleared  advance, so the empty state is its own step
  //
  // Decided from the current URL rather than remembered state: frame navigation
  // leaves this controller connected while the page underneath changes, so any
  // "what did I submit last" flag goes stale the moment you click a browse link.
  // Set on input rather than at submit time so pressing Enter uses it too.
  setHistoryAction() {
    // Path taken from the form's own action, so this doesn't hardcode the route.
    const searchPath = new URL(this.element.action, window.location.origin).pathname
    const refining = window.location.pathname === searchPath &&
                     this.inputTarget.value.trim() !== ""

    this.element.dataset.turboAction = refining ? "replace" : "advance"
  }

  // Show the ✕ only when there's text to clear.
  toggleClear() {
    if (this.hasClearTarget) this.clearTarget.hidden = this.inputTarget.value === ""
  }

  // Clear the typed query and reset the results (respecting any active scope).
  clearQuery(event) {
    event.preventDefault()
    this.inputTarget.value = ""
    this.toggleClear()
    this.inputTarget.focus()
    this.setHistoryAction()
    this.element.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}

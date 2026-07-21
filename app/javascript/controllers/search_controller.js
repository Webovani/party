import { Controller } from "@hotwired/stimulus"

// Debounced search: submits the form (which targets the search_results frame)
// a short moment after the user stops typing. Also manages the input's clear (✕)
// button and the browse-scope escape.
export default class extends Controller {
  static targets = ["input", "clear"]

  connect() {
    this.toggleClear()
  }

  submit() {
    clearTimeout(this.timer)
    this.timer = setTimeout(() => this.element.requestSubmit(), 300)
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
    this.element.requestSubmit()
  }

  // Escape browsing: drop the scope and search everywhere.
  clearScope(event) {
    event.preventDefault()
    const fields = document.getElementById("search-scope-fields")
    const chip = document.getElementById("search-scope-chip")
    if (fields) fields.innerHTML = ""
    if (chip) chip.hidden = true
    this.element.requestSubmit()
  }

  disconnect() {
    clearTimeout(this.timer)
  }
}

import { Controller } from "@hotwired/stimulus"

// Rendered (hidden) inside every search_results frame. On connect it pushes the
// frame's current browse scope into the persistent search form: hidden fields so
// the next search is scoped, and an "In: <label>" chip that also escapes browsing.
export default class extends Controller {
  static values = {
    browse: String, artist: String, album: String, path: String, label: String,
    listing: Boolean
  }

  connect() {
    // Navigating to a browse/history listing clears the search box so it matches
    // what's shown (rather than leaving a stale query behind).
    if (this.listingValue) {
      const input = document.querySelector('#search-form input[type="search"]')
      const clear = document.querySelector("#search-form .search-clear")
      if (input) input.value = ""
      if (clear) clear.hidden = true
    }

    const fields = document.getElementById("search-scope-fields")
    const chip = document.getElementById("search-scope-chip")
    if (!fields || !chip) return

    fields.replaceChildren()
    this.addField(fields, "browse", this.browseValue)
    this.addField(fields, "artist", this.artistValue)
    this.addField(fields, "album", this.albumValue)
    this.addField(fields, "path", this.pathValue)

    if (this.labelValue) {
      const label = chip.querySelector("[data-scope-chip-label]")
      if (label) label.textContent = this.labelValue
      chip.hidden = false
    } else {
      chip.hidden = true
    }
  }

  addField(container, name, value) {
    if (!value) return
    const input = document.createElement("input")
    input.type = "hidden"
    input.name = name
    input.value = value
    container.appendChild(input)
  }
}

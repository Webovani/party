import { Controller } from "@hotwired/stimulus"

// Rendered (hidden) inside every search_results frame, so its values describe the
// page actually being shown. Frame navigation does not re-render the search
// controls above the frame, so this pushes the scope back into them: hidden
// fields, placeholder, and the query — which is what keeps the box honest after a
// back/forward. A missed connect degrades to "briefly stale", not "stuck
// forever".
export default class extends Controller {
  static values = {
    browse: String, artist: String, album: String, path: String,
    query: String, placeholder: String
  }

  connect() {
    this.syncFields()
    this.syncInput()
  }

  syncFields() {
    const fields = document.getElementById("search-scope-fields")
    if (!fields) return

    fields.replaceChildren()
    for (const name of ["browse", "artist", "album", "path"]) {
      const value = this[`${name}Value`]
      if (!value) continue

      const input = document.createElement("input")
      input.type = "hidden"
      input.name = name
      input.value = value
      fields.appendChild(input)
    }
  }

  syncInput() {
    const input = document.querySelector('#search-form input[type="search"]')
    if (!input) return

    // Safe even mid-typing: a placeholder only shows while the field is empty.
    if (this.placeholderValue) input.placeholder = this.placeholderValue

    // The query is not. A debounced response carries the text as it was a debounce
    // interval ago (see search_controller), so overwriting would eat anything
    // typed since.
    if (document.activeElement === input || input.value === this.queryValue) return

    input.value = this.queryValue
    const clear = document.querySelector("#search-form .search-clear")
    if (clear) clear.hidden = this.queryValue === ""
  }
}

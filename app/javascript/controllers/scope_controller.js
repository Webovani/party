import { Controller } from "@hotwired/stimulus"

// Rendered (hidden) inside every search_results frame. Frame navigation does not
// re-render the search controls above, so this pushes the frame's browse scope
// into the form's hidden fields, keeping the next search scoped. On a full page
// load the server already rendered them; both derive from the same scope.
//
// The input's placeholder and value are handled by search_sync.js instead — they
// live inside a data-turbo-permanent element, which needs ordering guarantees a
// controller in here cannot give.
export default class extends Controller {
  static values = {
    browse: String, artist: String, album: String, path: String
  }

  connect() {
    const fields = document.getElementById("search-scope-fields")
    if (!fields) return

    fields.replaceChildren()
    this.addField(fields, "browse", this.browseValue)
    this.addField(fields, "artist", this.artistValue)
    this.addField(fields, "album", this.albumValue)
    this.addField(fields, "path", this.pathValue)
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

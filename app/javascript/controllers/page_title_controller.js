import { Controller } from "@hotwired/stimulus"

// The document head is never re-rendered after the first paint; the now-playing
// frame is. Carries the title forward on a track change.
export default class extends Controller {
  static values = { text: String }

  textValueChanged() {
    if (this.textValue) document.title = this.textValue
  }
}

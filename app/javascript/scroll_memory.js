// Scroll handling for frame navigation, which Turbo does not do for us: going
// forward starts at the top, going back returns you where you were.
//
// NOT a Stimulus controller, deliberately. A back-navigation is a full page
// render, so the element is destroyed and rebuilt — any state held on a
// controller instance (and any listener bound in connect()) dies during the very
// navigation this exists to handle. Module scope outlives page renders; the
// module is imported once.
//
// Also note .scroll is NOT the scroller despite its name and `overflow-y: auto`:
// .app is `min-height: 100dvh` rather than a fixed height, so the column grows
// with its content and the overflow never engages — the document scrolls. (Hence
// .topbar needing `position: sticky`.) Both are set, in case that ever changes.

const LIMIT = 30 // remembered URLs; a party session never needs more

const positions = new Map()
let restoring = false

// Sampled while scrolling rather than on the way out: by the time a frame
// navigation emits an event the URL has already advanced, so there is no moment
// at which "current URL + current scroll" still describes the page being left.
function remember() {
  positions.set(window.location.href, window.scrollY)
  if (positions.size > LIMIT) positions.delete(positions.keys().next().value)
}

// After paint: replacing a tall list with a short one lets the browser adjust
// scroll itself (scroll anchoring), which would land after a synchronous set.
function scrollToY(y) {
  requestAnimationFrame(() => {
    const pane = document.querySelector(".scroll")
    if (pane) pane.scrollTop = y
    window.scrollTo(0, y)
  })
}

function onRender(event) {
  if (restoring) {
    restoring = false
    const previous = positions.get(window.location.href)
    if (previous !== undefined) scrollToY(previous)
    return
  }

  // Only a frame navigation scrolls to the top. turbo:load ALSO fires for a
  // broadcast morph refresh — which happens every time anyone adds a song, and
  // arrives unprompted — so treating it as navigation yanked everyone to the top
  // mid-scroll. It is only listened to for the restoration case above.
  if (event.type !== "turbo:frame-render" || event.target.id !== "search_results") return

  // Search-as-you-type re-renders the frame on every keystroke; jumping would
  // fight the user. A browse link blurs the input first, so navigation scrolls.
  const input = document.querySelector('#search-form input[type="search"]')
  if (input && document.activeElement === input) return

  scrollToY(0)
}

window.addEventListener("scroll", remember, { passive: true })
window.addEventListener("popstate", () => { restoring = true })
// Frame navigation fires the first; a restoration visit is a full page render
// and fires the second. Exactly one fires per navigation, so they can't fight.
document.addEventListener("turbo:frame-render", onRender)
document.addEventListener("turbo:load", onRender)

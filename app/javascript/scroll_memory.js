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

// Restores only on a back/forward; any other full render is a fresh visit, which
// the browser already puts at the top.
function onLoad() {
  if (!restoring) return
  restoring = false

  const previous = positions.get(window.location.href)
  if (previous !== undefined) scrollToY(previous)
}

// Only the browse frame scrolls to the top. The queue and player frames reload
// unprompted whenever anyone touches the party — scrolling there would yank
// everyone to the top mid-scroll.
function onFrameRender(event) {
  if (event.target.id !== "search_results") return

  // Search-as-you-type re-renders the frame on every keystroke; jumping would
  // fight the user. A browse link blurs the input first, so navigation scrolls.
  const input = document.querySelector('#search-form input[type="search"]')
  if (input && document.activeElement === input) return

  scrollToY(0)
}

window.addEventListener("scroll", remember, { passive: true })
window.addEventListener("popstate", () => { restoring = true })
document.addEventListener("turbo:frame-render", onFrameRender)
document.addEventListener("turbo:load", onLoad)

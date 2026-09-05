// PartyBroadcaster sends "this region is stale", never its HTML, so a burst of
// changes is a burst of reload signals for one frame.
//
//   coalesce - reload on the first signal, then once at the end of the burst.
//   hold     - a control can suspend reloads of its own frame while it is worked.
//
// Deferred, never dropped: the frame still lands on the server's value.
const COALESCE_MS = 150

const frames = new Map() // frame id -> { held, pending, holdTimer, coalesceTimer }

export function reloadFrame(id) {
  const frame = stateFor(id)
  if (frame.held || frame.coalesceTimer) {
    frame.pending = true
    return
  }
  fetchFrame(id, frame)
}

// `ms` is measured from the last call, so repeated taps extend the hold.
export function holdFrame(id, ms) {
  const frame = stateFor(id)
  frame.held = true
  clearTimeout(frame.holdTimer)
  frame.holdTimer = setTimeout(() => {
    frame.held = false
    if (frame.pending && !frame.coalesceTimer) fetchFrame(id, frame)
  }, ms)
}

function fetchFrame(id, frame) {
  frame.pending = false
  document.getElementById(id)?.reload()

  frame.coalesceTimer = setTimeout(() => {
    frame.coalesceTimer = null
    if (frame.pending && !frame.held) fetchFrame(id, frame)
  }, COALESCE_MS)
}

function stateFor(id) {
  if (!frames.has(id)) frames.set(id, { held: false, pending: false, holdTimer: null, coalesceTimer: null })
  return frames.get(id)
}

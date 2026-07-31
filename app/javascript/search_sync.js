// Keeps the search box agreeing with the page it is on.
//
// The input lives inside #search-input-wrap, which is data-turbo-permanent so a
// morph broadcast can't eat what someone is typing. Permanent means Turbo carries
// the OLD element into every render and discards the server's markup — so the
// placeholder and the query can ONLY be updated by script, however correct the
// server-rendered version is.
//
// Module scope with document listeners, not a Stimulus controller: this must run
// after Turbo has swapped the permanent element into the new page, and a
// controller living inside the re-rendered frame has no guaranteed ordering
// against that swap. (Same reason scroll_memory isn't a controller.)
//
// The values come from the scope element, which IS re-rendered every navigation,
// so it always describes the page actually being shown.

function sync(event) {
  if (event?.type === "turbo:frame-render" && event.target.id !== "search_results") return

  const source = document.querySelector("[data-scope-placeholder-value]")
  const input = document.querySelector('#search-form input[type="search"]')
  if (!source || !input) return

  const placeholder = source.getAttribute("data-scope-placeholder-value")
  // Safe even mid-typing: a placeholder only shows while the field is empty.
  if (placeholder) input.placeholder = placeholder

  // The query is not: a debounced response carries the text as it was a debounce
  // interval ago (see search_controller), so overwriting would eat anything typed
  // since.
  if (document.activeElement === input) return

  const query = source.getAttribute("data-scope-query-value") || ""
  if (input.value === query) return

  input.value = query
  const clear = document.querySelector("#search-form .search-clear")
  if (clear) clear.hidden = query === ""
}

document.addEventListener("turbo:load", sync)
document.addEventListener("turbo:frame-render", sync)

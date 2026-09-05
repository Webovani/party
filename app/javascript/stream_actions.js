import { Turbo } from "@hotwired/turbo-rails"

// PartyBroadcaster sends "this region is stale", not its HTML (see there). The
// client refetches the frame's own `src` with its own cookies.
//
// Module scope: must be registered before the first broadcast arrives, which a
// controller inside re-rendered markup cannot promise.
Turbo.StreamActions.reload_frame = function () {
  document.getElementById(this.target)?.reload()
}

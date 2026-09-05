import { Turbo } from "@hotwired/turbo-rails"
import { reloadFrame } from "frame_reloads"

// PartyBroadcaster sends "this region is stale", not its HTML (see there). The
// client refetches the frame's own `src` with its own cookies.
//
// Module scope: must be registered before the first broadcast arrives, which a
// controller inside re-rendered markup cannot promise.
Turbo.StreamActions.reload_frame = function () {
  reloadFrame(this.target)
}

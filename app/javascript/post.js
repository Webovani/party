// Player controls POST and get 204 back — the result arrives as a broadcast frame
// reload, so there is nothing for Turbo to render.
export function post(url, params = {}) {
  const body = new FormData()
  for (const [key, value] of Object.entries(params)) body.append(key, value)

  return fetch(url, {
    method: "POST",
    body,
    headers: { "X-CSRF-Token": document.querySelector('meta[name="csrf-token"]')?.content }
  })
}

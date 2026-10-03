import "phoenix_html"
import {Socket} from "phoenix"
import {LiveSocket} from "phoenix_live_view"

let Hooks = {}

// Counts down from `data-remaining` ms, shown as m:ss. When it reaches zero it
// pushes `data-event` with `data-key`, so the server can ignore stale timers.
Hooks.Countdown = {
  mounted() {
    this.endsAt = Date.now() + Number(this.el.dataset.remaining)
    this.tick()
    this.interval = setInterval(() => this.tick(), 250)
  },
  destroyed() {
    clearInterval(this.interval)
  },
  tick() {
    const left = Math.max(0, Math.ceil((this.endsAt - Date.now()) / 1000))
    this.el.textContent = `${Math.floor(left / 60)}:${String(left % 60).padStart(2, "0")}`

    if (left === 0) {
      clearInterval(this.interval)
      if (this.el.dataset.event) this.pushEvent(this.el.dataset.event, {key: this.el.dataset.key})
    }
  }
}

let csrfToken = document.querySelector("meta[name='csrf-token']")?.getAttribute("content")
let liveSocket = new LiveSocket("/live", Socket, {
  hooks: Hooks,
  longPollFallbackMs: 2500,
  params: {_csrf_token: csrfToken}
})

liveSocket.connect()

window.liveSocket = liveSocket

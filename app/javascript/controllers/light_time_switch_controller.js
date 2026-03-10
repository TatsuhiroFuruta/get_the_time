import { Controller } from "@hotwired/stimulus"
import { Turbo } from "@hotwired/turbo-rails"

// Connects to data-controller="light-time-switch"
export default class extends Controller {

  connect() {
    this.light_times = JSON.parse(this.element.dataset.light_times)
    const currentId = Number(this.element.dataset.currentId)
    this.index = this.light_times.indexOf(currentId)

    this.keyHandler = this.handleKey.bind(this)
    window.addEventListener("keydown", this.keyHandler)
  }

  disconnect() {
    window.removeEventListener("keydown", this.keyHandler)
  }

  handleKey(event) {
    const isDesktop = window.matchMedia("(min-width: 768px)").matches

    if (isDesktop) {
      // 広い画面 → 上下のみ
      if (event.key === "ArrowDown") {
        this.next()
      }
      if (event.key === "ArrowUp") {
        this.prev()
      }
    } else {
      // 狭い画面 → 左右のみ
      if (event.key === "ArrowRight") {
        this.next()
      }
      if (event.key === "ArrowLeft") {
        this.prev()
      }
    }
  }

  next() {
    if (this.index < this.light_times.length - 1) {
      this.index++
      this.switch()
    }
  }

  prev() {
    if (this.index > 0) {
      this.index--
      this.switch()
    }
  }

  switch() {
    const id = this.light_times[this.index]

    fetch(`/light_times/${id}/switch`, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content,
        "Accept": "text/vnd.turbo-stream.html"
      },
      credentials: "same-origin"
    })
    .then(response => response.text())
    .then(html => Turbo.renderStreamMessage(html))
  }
}

import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="pomodoro-setting-modal"
export default class extends Controller {
  static targets = ["modal", "overlay"]

  open() {
    this.modalTarget.classList.remove("hidden")
    document.body.classList.add("overflow-hidden")
  }

  close() {
    this.modalTarget.classList.add("hidden")
    document.body.classList.remove("overflow-hidden")
  }

  closeOnOverlay(event) {
    if (event.target === this.overlayTarget) {
      this.close()
    }
  }
}

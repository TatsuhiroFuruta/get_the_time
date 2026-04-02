import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="purification-timer"
export default class extends Controller {
  static targets = ["display"]
  static values = {
    remaining: Number,
    startedAt: Number,
    running: Boolean
  }

  connect() {
    this.audio = new Audio('/sounds/notification.mp3')
    this.audio.volume = 0.5

    this.update()

    if (this.runningValue) {
      this.startCountdown()
    }
  }

  startCountdown() {
    this.timer = setInterval(() => {
      this.update()
    }, 1000)
  }

  update() {
    let remaining = this.remainingValue

    if (this.runningValue && this.hasStartedAtValue) {
      const now = Math.floor(Date.now() / 1000)
      const elapsed = now - this.startedAtValue
      remaining = Math.max(this.remainingValue - elapsed, 0)
    }

    this.currentRemaining = remaining
    this.displayTarget.textContent = this.format(this.currentRemaining)

    if (remaining <= 0 && this.runningValue) {
      clearInterval(this.timer)
      // ✅ チャイム音を再生、自動終了
      this.playSound()
    }
  }

  format(remaining) {
    const minutes = Math.floor(remaining / 60)
    const seconds = remaining % 60
    return `${minutes}:${seconds.toString().padStart(2, '0')}`
  }

  start() {
    this.request("/purification_time/start")
  }

  stop(redirect = true) {
    this.request("/purification_time/stop", redirect)
  }

  request(url, redirect = false) {
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": document.querySelector("meta[name='csrf-token']").content
      }
    }).then(() => {
      if (redirect) {
        location.replace("/mypage")
      } else {
        location.reload()
      }
    })
  }

  // ✅ 音声を再生するメソッド
  playSound() {
    this.audio.currentTime = 0
    this.audio.play().catch(() => {})

    this.audio.onended = () => {
      this.stop() // 自動終了
    }
  }

  disconnect() {
    clearInterval(this.timer)
  }
}

import { Controller } from "@hotwired/stimulus"
import { heldByOther } from "../lib/activity_lock"

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

    // displayTargetが存在し、かつ残り時間がある場合のみ更新
    if (this.hasDisplayTarget && this.remainingValue > 0) {
      this.update()
    }

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
    // ✅ 別タブが光の時間の活動中なら、スタート押下の瞬間に弾く。画面を開いた
    // 時点のガード（activity-lock コントローラ）だけでは、両タブを開いた後で
    // ポモドーロが後から開始されたケースを検知できない。
    if (heldByOther()) {
      location.replace("/mypage?locked=activity")
      return
    }

    this.request("/purification_time/start")
  }

  stop(redirect = true) {
    this.request("/purification_time/stop", redirect)
  }

  reset() {
    fetch("/purification_time", {
      headers: { "Accept": "application/json" }
    })
      .then(res => res.json())
      .then(data => {
        if (data.running) {
          alert("タイマー実行中です")
          // 軽く待ってからリロード（UX改善）
          setTimeout(() => {
            location.reload()
          }, 300)
          return
        }

        if (!confirm("本当にタイマーをリセットしてもよろしいでしょうか？")) return

        this.request("/purification_time/reset")
      })
  }

  request(url, redirect = false) {
    const csrfToken = document.querySelector("meta[name='csrf-token']")?.content
    fetch(url, {
      method: "PATCH",
      headers: {
        "X-CSRF-Token": csrfToken || ""
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

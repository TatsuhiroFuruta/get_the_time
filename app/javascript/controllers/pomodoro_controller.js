import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="pomodoro"
export default class extends Controller {
  static targets = ["display", "startButton"]
  static values = {
    workDuration: { type: Number, default: 1500 }
  }

  connect() {
    this.remainingTime = this.workDurationValue
    this.timerInterval = null
    this.endedAt = null

    // ✅ 最初のタイマー開始時刻を保持
    this.firstStartedAt = null

    this.updateTimeDisplay()
  }

  disconnect() {
    if (this.timerInterval) {
      clearInterval(this.timerInterval)
    }
  }

  start() {
    if (this.timerInterval) return

    // ✅ 最初のスタート時のみ記録
    if (this.firstStartedAt === null) {
      this.firstStartedAt = new Date()
    }

    this.endedAt = this.getEndedAt(new Date(), this.workDurationValue)

    this.startTimer()
    this.startButtonTarget.classList.add("hidden")
  }

  // ✅ 破壊的でない実装にする
  getEndedAt(startedAt, duration) {
    return new Date(startedAt.getTime() + duration * 1000)
  }

  startTimer() {
    this.timerInterval = setInterval(() => {
      this.remainingTime = Math.ceil((this.endedAt - new Date()) / 1000)
      this.updateTimeDisplay()

      if (this.remainingTime <= 0) {
        this.onTimerComplete()
      }
    }, 1000)
  }

  onTimerComplete() {
    clearInterval(this.timerInterval)
    this.timerInterval = null

    this.remainingTime = this.workDurationValue

    this.updateTimeDisplay()
    this.startButtonTarget.classList.remove("hidden")
    // ✅ チャイム音を再生
    this.playSound('/sounds/notification.mp3')
  }

  updateTimeDisplay() {
    const minutes = Math.floor(this.remainingTime / 60)
    const seconds = this.remainingTime % 60
    this.displayTarget.textContent = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
  }

  // ✅ 音声を再生するメソッド
  playSound(soundPath) {
    const audio = new Audio(soundPath)

    // 音量を設定（0.0 〜 1.0）
    audio.volume = 0.5

    // 再生
    audio.play().catch(error => {
      console.log('音声再生に失敗しました:', error)
      // ユーザーがまだページと対話していない場合に失敗することがある
    })
  }
}

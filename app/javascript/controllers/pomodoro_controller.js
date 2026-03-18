import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="pomodoro"
export default class extends Controller {
  static targets = ["workScreen", "breakScreen", "display", "savedTask", "taskInput", "startButton", "pomodoroCount"]
  static values = {
    workDuration: { type: Number, default: 1500 },
    breakDuration: { type: Number, default: 300 },
    task: {type: String, default: null}
  }

  connect() {
    this.mode = "work"
    this.pomodoroCount = 0
    this.remainingTime = this.workDurationValue
    this.timerInterval = null
    this.endedAt = null
    this.task = this.taskValue
    // 追記して修正できるように、マイページで入力した内容をやることの入力フォームに残しておく。
    this.taskInputTarget.value = this.task

    // ✅ 最初のタイマー開始時刻を保持
    this.firstStartedAt = null

    // ✅ beforeunload イベントリスナーを追加
    this.boundBeforeUnloadHandler = this.handleBeforeUnload.bind(this)

    this.updateTimeDisplay()
    this.updatePomodoroCount()

    this.startButtonTarget.classList.remove("hidden")
  }

  disconnect() {
    // ✅ コントローラーが破棄される時にイベントリスナーを削除
    this.removeBeforeUnloadListener()

    if (this.timerInterval) {
      clearInterval(this.timerInterval)
    }
  }

  // タイトル更新（デバウンス付き）
  updateTaskDisplay() {
    this.task = this.taskInputTarget.value
    this.savedTaskTarget.textContent = this.task ? this.task : "フォームに入力して「更新する」をクリック！"
    // 前に入力した内容をinputタグに残すことに！
    // this.taskInputTarget.value = ''
  }

  start() {
    if (this.timerInterval) return

    // ✅ 最初のスタート時のみ記録
    if (this.firstStartedAt === null) {
      this.firstStartedAt = new Date()
      // ✅ 離脱警告を有効化
      this.addBeforeUnloadListener()
    }

    if (this.mode === "work") {
      this.endedAt = this.getEndedAt(new Date(), this.workDurationValue)
    }

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

    if (this.mode === "work") {
      this.pomodoroCount++
      this.updatePomodoroCount()
      this.switchToBreakMode()
    } else {
      this.switchToWorkMode()
    }
  }

  switchToWorkMode() {
    this.mode = "work"

    this.endedAt = this.getEndedAt(new Date(), this.workDurationValue)
    this.remainingTime = this.workDurationValue

    this.updateTimeDisplay()
    this.showWorkScreen()
    this.startButtonTarget.classList.remove("hidden")
    // ✅ チャイム音を再生
    this.playSound('/sounds/notification.mp3')
  }

  switchToBreakMode() {
    this.mode = "break"
    this.remainingTime = this.breakDurationValue
    this.endedAt = this.getEndedAt(new Date(), this.breakDurationValue)

    this.updateTimeDisplay()
    this.showBreakScreen()
    // ✅ チャイム音を再生
    this.playSound('/sounds/notification.mp3')
    this.startTimer()
  }

  showWorkScreen() {
    this.breakScreenTarget.classList.add("hidden")
    this.workScreenTarget.classList.remove("hidden")
  }

  showBreakScreen() {
    this.workScreenTarget.classList.add("hidden")
    this.breakScreenTarget.classList.remove("hidden")
  }

  updateTimeDisplay() {
    const minutes = Math.floor(this.remainingTime / 60)
    const seconds = this.remainingTime % 60

    const text = `${String(minutes).padStart(2, '0')}:${String(seconds).padStart(2, '0')}`
    this.displayTargets.forEach(el => {
      el.textContent = text
    })
  }

  updatePomodoroCount() {
    this.pomodoroCountTargets.forEach(el => {
      el.textContent = this.pomodoroCount
    })
  }

  // ✅ beforeunload イベントハンドラー
  handleBeforeUnload(event) {
    event.preventDefault()
    // モダンブラウザでは戻り値は無視されるが、互換性のため設定
    event.returnValue = ''
    return ''
  }

  // ✅ イベントリスナーを追加
  addBeforeUnloadListener() {
    window.addEventListener('beforeunload', this.boundBeforeUnloadHandler)
  }

  // ✅ イベントリスナーを削除
  removeBeforeUnloadListener() {
    window.removeEventListener('beforeunload', this.boundBeforeUnloadHandler)
  }

  // ✅ 音声を再生するメソッド
  playSound(soundPath) {
    const audio = new Audio(soundPath)

    // 音量を設定（0.0 〜 1.0）
    audio.volume = 0.5

    // 再生
    audio.play().catch(() => {
      // ユーザーがまだページと対話していない場合に失敗することがある
    })
  }
}

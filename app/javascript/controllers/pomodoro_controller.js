import { Controller } from "@hotwired/stimulus"

// Connects to data-controller="pomodoro"
export default class extends Controller {
  static targets = ["workScreen", "breakScreen", "motivationScreen", "display", "savedTask", "taskInput", "startButton", "pomodoroCount"]
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

    // 寝落ちチェックのための時刻
    this.lastActivityAt = null

    this.isMotivationOpen = false

    // ✅ 本番用の設定
    // this.inactivityTimeout = 5 * 60 * 1000  // 5分
    // this.checkInterval = 60 * 1000  // 1分ごとにチェック

    // ✅ テスト用の設定（動作確認時はこちらを使用）
    this.inactivityTimeout = 60 * 1000  // 1分
    this.checkInterval = 5 * 1000  // 5秒ごとにチェック

    // ✅ beforeunload イベントリスナーを追加
    this.boundBeforeUnloadHandler = this.handleBeforeUnload.bind(this)

    this.updateTimeDisplay()
    this.updatePomodoroCount()

    // 初期画面の表示でセット
    this.updateUI()

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

    // ✅ タイマー開始時は無操作チェックを停止
    this.stopInactivityCheck()

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
    // 活動時間の計測画面へと遷移
    this.updateUI()
    this.startButtonTarget.classList.remove("hidden")
    // ✅ チャイム音を再生
    this.playSound('/sounds/notification.mp3')
    this.updateLastActivity()
    this.startInactivityCheck()
  }

  switchToBreakMode() {
    this.mode = "break"
    this.remainingTime = this.breakDurationValue
    this.endedAt = this.getEndedAt(new Date(), this.breakDurationValue)

    this.updateTimeDisplay()
    // 休憩時間の画面へと遷移
    this.updateUI()
    // ✅ チャイム音を再生
    this.playSound('/sounds/notification.mp3')
    this.startTimer()
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

  // ✅ 無操作チェックの開始
  startInactivityCheck() {
    if (this.inactivityCheckInterval) return

    this.inactivityCheckInterval = setInterval(() => {
      this.checkInactivity()
    }, this.checkInterval)
  }

   // ✅ 無操作チェックの停止
  stopInactivityCheck() {
    if (this.inactivityCheckInterval) {
      clearInterval(this.inactivityCheckInterval)
      this.inactivityCheckInterval = null
    }
  }

  // ✅ 無操作チェック
  checkInactivity() {
    // タイマーが動いている時はチェックしない
    if (this.timerInterval) return

    if (!this.lastActivityAt) return

    const now = new Date()
    const timeSinceLastActivity = now - this.lastActivityAt

    // 5分以上操作がない場合
    if (timeSinceLastActivity >= this.inactivityTimeout) {
      // console.log("休憩後5分経過: 自動的に記録を保存します")

      this.stopInactivityCheck()
      this.removeBeforeUnloadListener()

      this.saveActivityRecordWithInactivityTimeout()
    }
  }

  // ✅ 最終操作時刻を更新
  updateLastActivity() {
    this.lastActivityAt = new Date()
  }

  // ✅ 無操作タイムアウト時の記録保存
  saveActivityRecordWithInactivityTimeout() {
    if (!this.firstStartedAt || !this.lastActivityAt) {
      alert("記録を保存できませんでした")
      return
    }

    // 最終操作時刻を終了時刻として使用
    const lastEndedAt = this.lastActivityAt

    const params = this.saveActivityRecord(lastEndedAt)

    // アラート文を表示
    alert(`操作がなかったため、自動的に記録を保存します。`)

    setTimeout(() => {
      location.replace(`/activity_records/new?${params.toString()}`)
    }, 300)
  }

  updateUI() {
    // 通常画面
    this.workScreenTarget.classList.toggle("hidden", this.mode !== "work" || this.isMotivationOpen)

    this.breakScreenTarget.classList.toggle("hidden", this.mode !== "break" || this.isMotivationOpen)

    // motivation画面
    this.motivationScreenTarget.classList.toggle("hidden", !this.isMotivationOpen)
  }

  toggleMotivation() {
    this.isMotivationOpen = !this.isMotivationOpen
    this.updateUI()
  }

  finish() {
    const lastEndedAt = new Date()

    if (this.timerInterval) {
      clearInterval(this.timerInterval)
      this.timerInterval = null
    }

    // ✅ タイマー終了時に離脱警告を無効化
    this.removeBeforeUnloadListener()


    if (this.firstStartedAt) {
      // ✅ 最初のスタート時刻からの差分を計算
      const params = this.saveActivityRecord(lastEndedAt)
      // ✅ 確認フォーム画面に遷移
      location.replace(`/activity_records/new?${params.toString()}`)
    } else {
      alert("スタートボタンを押してください")
    }
  }

  saveActivityRecord(lastEndedAt) {
    // ✅ 最初のスタート時刻からの差分を計算
    // const durationInSeconds = Math.floor((lastEndedAt - this.firstStartedAt) / 1000)
    const durationInMinutes = Math.floor((lastEndedAt - this.firstStartedAt) / 60000)

    // ✅ URLパラメータとして渡す
    const params = new URLSearchParams({
      'activity_record_form[task]': this.task,
      'activity_record_form[started_at]': this.firstStartedAt.toISOString(),
      'activity_record_form[ended_at]': lastEndedAt.toISOString(),
      'activity_record_form[total_duration]': durationInMinutes
    })
    return params
  }
}

import { Controller } from "@hotwired/stimulus"
import { acquire, renew, release as releaseLock, heldByOther, HEARTBEAT_MS } from "../lib/activity_lock"

// 「光の時間の活動」リースを画面に貼るための薄いコントローラ。
//
//   hold:       true なら connect 時にロックを取り、以後 heartbeat で更新し続ける
//   redirectTo: 他タブがロックを持っていたら、この URL へ引き返す
//
// Connects to data-controller="activity-lock"
export default class extends Controller {
  static values = {
    hold: { type: Boolean, default: false },
    redirectTo: { type: String, default: "" }
  }

  connect() {
    // localStorage の読み取りは同期なので、判定とリダイレクトは connect と
    // 同じティックで走る。画面のちらつきはほぼ発生しない。
    if (this.redirectToValue && heldByOther()) {
      location.replace(this.redirectToValue)
      return
    }

    if (this.holdValue) {
      acquire()
      this.heartbeat = setInterval(() => renew(), HEARTBEAT_MS)
    }
  }

  // 活動記録フォームの送信時に呼ぶ（Task 5 で form に data-action を貼る）。
  // 登録が完了すればロックは不要なので、TTL を待たずに解放する。
  // バリデーションエラーで new が再描画された場合は connect が再度 acquire するので、
  // 送信が失敗しても壊れない。
  release() {
    releaseLock()
    clearInterval(this.heartbeat)
  }

  disconnect() {
    // ここで releaseLock() は呼ばない。離脱の種類（ブラウザバック / タブ閉じ /
    // 正常遷移）を区別し始めた瞬間に、PR #88 と同じ破綻が戻ってくる。
    // 更新が止まればリースは TTL で勝手に腐る。
    clearInterval(this.heartbeat)
  }
}

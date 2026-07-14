import { Controller } from "@hotwired/stimulus"
import { acquire, renew, release as releaseLock, heldByOther, orphan, HEARTBEAT_MS } from "../lib/activity_lock"

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
    this.boundGuard = this.guard.bind(this)
    // storage: 他タブがロックを書き込んだ瞬間に「他タブ側」だけで発火するイベント。
    // これにより、開きっぱなしのこの画面が、後から別タブでロックが取られた
    // 瞬間に自分から追い返される。
    // pageshow: bfcache からの復元をカバーする。Stimulus の connect() は
    // bfcache 復元時には再実行されないため、これが無いと復元後にガードが働かない。
    window.addEventListener("storage", this.boundGuard)
    window.addEventListener("pageshow", this.boundGuard)

    // localStorage の読み取りは同期なので、判定とリダイレクトは connect と
    // 同じティックで走る。画面のちらつきはほぼ発生しない。
    if (this.guard()) return

    if (this.holdValue) {
      acquire()
      this.heartbeat = setInterval(() => renew(), HEARTBEAT_MS)
    }
  }

  // 他タブが有効なロックを持っていれば redirectTo へ引き返す。redirectTo が
  // 無い画面（保持専用の記録フォーム等）では何もしない。
  guard() {
    if (this.redirectToValue && heldByOther()) {
      location.replace(this.redirectToValue)
      return true
    }
    return false
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
    clearInterval(this.heartbeat)
    window.removeEventListener("storage", this.boundGuard)
    window.removeEventListener("pageshow", this.boundGuard)

    // Turbo Drive はページ内リンクの遷移で document を作り直さないため、
    // pagehide は発火しない。Stimulus の disconnect() は Turbo 遷移でも
    // 確実に呼ばれるので、ここでも自分のロックを orphan（期限を 5 秒に短縮）
    // しておく。release() ではなく orphan() を使うのは pagehide と同じ理由:
    // 同一タブでフォームへ正常遷移する場合、遷移先の connect() が 1 秒以内に
    // acquire() し直して満了期限を戻すので、削除ではなく短縮で十分かつ安全。
    orphan()
  }
}

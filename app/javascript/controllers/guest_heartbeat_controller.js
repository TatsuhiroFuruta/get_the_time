import { Controller } from "@hotwired/stimulus"
import { held } from "../lib/activity_lock"

// ゲストが「まだ見ている」ことをサーバへ定期的に伝える。
//
// ポモドーロも浄化タイマーも、計測はすべてクライアント側で完結している
// （pomodoro_controller の startTimer / onTimerComplete、purification_timer_controller の
// カウントダウン）。30秒ごとの heartbeat も localStorage を書くだけでサーバへは出ない。
// つまり計測中はサーバへのリクエストがゼロで、last_request_at が更新されないまま
// GuestUserPurger の削除対象（1時間無操作）に入ってしまう。
// 既定の 25分 + 休憩5分 + 25分 で 55分、作業時間は最大90分まで設定できる。
//
// 計測画面ごとに仕込むのではなく、レイアウトから常時動かす。silent な画面を列挙する
// 方式は、画面が増えたときに漏れるため。
//
// 実際の UPDATE は ApplicationController#touch_guest_activity が10分に間引くので、
// この間隔を短くしても DB への書き込みは増えない。
//
// Connects to data-controller="guest-heartbeat"
export default class extends Controller {
  static values = { interval: { type: Number, default: 60000 } }

  connect() {
    this.timer = setInterval(() => this.ping(), this.intervalValue)
  }

  disconnect() {
    clearInterval(this.timer)
    this.timer = null
  }

  ping() {
    // 見えているか、計測中なら送る。
    //
    // 非表示というだけで止めてはいけない。ポモドーロは「タイマーを開始して別タブで
    // 作業する」のが通常の使い方で（activity_lock.js の intensive throttling の
    // コメントを参照）、そこで ping が止まると last_request_at が凍り、計測中の
    // ゲストが削除されうる。このコントローラを足した理由そのものが失われる。
    //
    // 一方、計測していない放置タブまで生かし続ける必要はない。リースの有無で
    // 「計測中か」を判定し、放置タブは通常どおり削除対象へ落とす。
    if (document.visibilityState !== "visible" && !held()) return

    const token = document.querySelector('meta[name="csrf-token"]')?.content

    // 失敗しても画面の機能には影響しない（次の周期で再試行される）ので握りつぶす。
    // ゲストが既に削除されていれば認証に弾かれるが、その場合も次の操作で
    // ログイン画面へ案内されるので、ここで何かする必要はない。
    fetch("/guest_heartbeat", {
      method: "POST",
      headers: { "X-CSRF-Token": token, Accept: "application/json" }
    }).catch(() => {})
  }
}

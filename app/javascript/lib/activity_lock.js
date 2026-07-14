// 「光の時間の活動中（ポモドーロ計測〜活動記録の登録完了）」を表す、期限付きのリース。
//
// ポモドーロの状態はブラウザのメモリにしか無く、信頼できる終了シグナルが存在しない
// （ブラウザバック・タブ閉じ・記録せず離脱が、すべて「通知なき終了」になる）。
// そのため「明示的にクリアしないと消えないフラグ」で表すと、消し損ねた瞬間に
// ユーザーが恒久的にロックアウトされる。
//
// ここでは代わりに、更新され続けている間だけ生きているリースとして表す。
// 更新が止まれば勝手に腐るので、離脱の種類を区別するコードは一切書かない。

const LOCK_KEY = "gtt:activity_lock"
const TAB_KEY = "gtt:tab_id"

// ブラウザは非表示タブの setInterval を絞る。Chrome は 5 分ほど隠れたタブの
// タイマーを「1 分に 1 回」まで落とす（intensive throttling）。
// ポモドーロ中に別タブへ切り替えるのはまさにこの機能が想定している状況なので、
// heartbeat が 1 分に 1 回まで落ちてもリースが切れない値を選ぶ必要がある。
// TTL を数秒に設定すると、25 分のセッションのうち最初の 5 分しか排他が効かない。
export const TTL_MS = 180000        // ロックの有効期間（3 分）
export const HEARTBEAT_MS = 30000   // 更新間隔（30 秒）。絞られて 1 分間隔になっても TTL に届く

// 離脱時にリースへ与える猶予。削除ではなく期限の短縮にとどめるのが要点。
// 「本当の離脱」と「フォームへの正常遷移」を区別しないまま、両方を正しく扱える:
//   - 正常遷移なら、遷移先のページが 1 秒以内に renew() して満了期限が戻る
//   - 本当の離脱なら、誰も更新しないので数秒で腐って消える
// 削除してしまうと遷移中の一瞬だけロックが空き、その隙に他タブが入れてしまう。
const ORPHAN_TTL_MS = 5000

// タブの同一性。sessionStorage はタブ単位で、同一タブ内のページ遷移では保持され、
// 別タブには引き継がれない。だからポモドーロ画面 → 活動記録フォームへ遷移しても
// 「同じ持ち主」としてリースを引き継げる。
function tabId() {
  let id = sessionStorage.getItem(TAB_KEY)
  if (!id) {
    id = `${Date.now()}-${Math.random().toString(36).slice(2)}`
    sessionStorage.setItem(TAB_KEY, id)
  }
  return id
}

// 現在有効なロックを返す。期限切れのロックは「無い」ものとみなす（掃除役は不要）。
function currentLock() {
  const raw = localStorage.getItem(LOCK_KEY)
  if (!raw) return null

  const lock = JSON.parse(raw)
  if (!lock || typeof lock.expiresAt !== "number") return null
  if (lock.expiresAt <= Date.now()) return null

  return lock
}

function write() {
  localStorage.setItem(
    LOCK_KEY,
    JSON.stringify({ owner: tabId(), expiresAt: Date.now() + TTL_MS })
  )
}

// プライベートモード等で Storage が例外を投げても、排他制御のために本来の機能を
// 壊さない。その場合は「ロックは無い」ものとして通常どおり動かす。
function safely(fn, fallback) {
  try {
    return fn()
  } catch {
    return fallback
  }
}

export function acquire() {
  return safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return false

    write()
    return true
  }, true)
}

// 他タブが有効なロックを持っているときだけ何もしない。ロックが無い・期限切れの
// ときは自分名義で書き直す（＝奪わないが、失った自分のリースは取り戻す）。
// この寛容さは意図的である。厳格に「自分のロックがあるときだけ延長」にすると、
// 何らかの理由で一度でも期限が切れたリースを二度と回復できず、まだ動いている
// ポモドーロが排他を永久に失う。他タブのロックは決して奪わないので安全側に倒れる。
export function renew() {
  safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return

    write()
  }, undefined)
}

export function release() {
  safely(() => {
    const lock = currentLock()
    if (lock && lock.owner !== tabId()) return

    localStorage.removeItem(LOCK_KEY)
  }, undefined)
}

export function heldByOther() {
  return safely(() => {
    const lock = currentLock()
    return Boolean(lock) && lock.owner !== tabId()
  }, false)
}

// このタブが離脱する（タブを閉じる / ブラウザバック / 遷移）ときに、自分のロックの
// 期限を短く詰める。すでに ORPHAN_TTL_MS より近い期限なら触らない。
export function orphan() {
  safely(() => {
    const lock = currentLock()
    if (!lock || lock.owner !== tabId()) return

    const expiresAt = Math.min(lock.expiresAt, Date.now() + ORPHAN_TTL_MS)
    localStorage.setItem(LOCK_KEY, JSON.stringify({ owner: lock.owner, expiresAt }))
  }, undefined)
}

// このモジュールを読み込むページは、離脱時に必ず自分のロックを orphan する。
// pagehide は離脱の種類（タブ閉じ・ブラウザバック・通常遷移）を問わず発火するが、
// ここでは区別しないことが正しい。区別を始めた瞬間に、明示的な後始末に依存する
// 設計へ逆戻りし、後始末を取りこぼしたユーザーが締め出される。
window.addEventListener("pagehide", orphan)

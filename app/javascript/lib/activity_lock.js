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

export const TTL_MS = 10000        // ロックの有効期間
export const HEARTBEAT_MS = 3000   // 更新間隔。TTL より十分に短くすること

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

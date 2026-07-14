class PurificationTime < ApplicationRecord
  belongs_to :user

  enum :status, { idle: 0, running: 1, paused: 2 }

  def finished?
    remaining_time.to_i <= 0
  end

  # 実時間ベースで「いま計測中か」を導出する。status だけを見ると、時間切れ後に
  # stop! が呼ばれないまま（タブを閉じた等）running が残り、ポモドーロを永久に
  # ブロックしてしまうため、排他制御の判定にはこちらを使う。
  def counting?
    running? && started_at.present? && Time.current < started_at + total_time
  end

  def start!
    return unless idle? || paused?

    update!(
      status: :running,
      started_at: Time.current,
      total_time: remaining_time
    )
  end

  def stop!
    return unless running?

    elapsed = (Time.current - started_at).to_i
    remaining = total_time - elapsed

    if remaining <= 0
      finish!
    else
      pause!(remaining)
    end
  end

  def reset!
    update!(
      status: :idle,
      remaining_time: 0,
      total_time: 0,
      started_at: nil,
      paused_at: nil
    )
  end

  private

  def pause!(remaining)
    update!(
      status: :paused,
      remaining_time: remaining,
      paused_at: Time.current
    )
  end

  def finish!
    update!(
      status: :idle,
      remaining_time: 0,
      total_time: 0,
      started_at: nil,
      paused_at: nil
    )
  end
end

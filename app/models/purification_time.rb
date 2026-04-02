class PurificationTime < ApplicationRecord
  belongs_to :user

  enum :status, { idle: 0, running: 1, paused: 2 }

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

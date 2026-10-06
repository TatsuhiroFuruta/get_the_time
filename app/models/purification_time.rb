class PurificationTime < ApplicationRecord
  belongs_to :user

  enum :status, { idle: 0, running: 1, paused: 2 }

  def finished?
    remaining_time.to_i <= 0
  end

  # 指定日にすでに払い出した浄化タイマーのブロック数。
  #
  # 当日の光の時間の累計は活動記録から導出できるが、記録が削除されると減る。
  # 累計だけで「何ブロック付与済みか」を判断すると、29 分ためた状態で 1 分の記録を
  # 作っては消す操作で何度でも付与できてしまうため、払い出した実績はここに残す。
  #
  # 累計は 0 時にリセットされるので、台帳の日付が違えば 0 とみなす。
  def granted_blocks_for(date)
    granted_blocks_date == date ? granted_blocks_count.to_i : 0
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

  # 浄化タイマーに時間を付与する。保存は呼び出し側（PurificationTimeGranter）が
  # 払い出し台帳と一緒に 1 回で行うので、ここでは属性の代入だけにとどめる。
  #
  # running 中の残り時間は remaining_time ではなく total_time - 経過秒 で計算される
  # （stop! / counting?）。remaining_time にだけ足すと次の stop! で付与分が消えるため、
  # 状態に応じて次のように扱う。
  #   - 計測中: total_time も延ばし、終了予定時刻を後ろへずらす。修正前（#282）の付与で
  #     remaining_time > total_time になったデータもあるため、本来の残りである
  #     remaining_time に揃えてから延ばし、running 中の remaining_time == total_time を保つ
  #   - 期限切れのまま running で残っている: 先に終了扱い（idle・残り 0）に精算してから足す。
  #     延ばしても期限がまだ過去にあれば結局 0 になるうえ、精算すれば counting? が
  #     false のままなのでポモドーロもブロックしない
  def add_time(seconds)
    if running?
      if counting?
        self.total_time = remaining_time + seconds
      else
        assign_attributes(finished_attributes)
      end
    end

    self.remaining_time += seconds
  end

  def reset!
    update!(finished_attributes)
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
    update!(finished_attributes)
  end

  def finished_attributes
    {
      status: :idle,
      remaining_time: 0,
      total_time: 0,
      started_at: nil,
      paused_at: nil
    }
  end
end

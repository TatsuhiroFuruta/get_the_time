class RegretSummariesController < ApplicationController
  before_action :set_regret_summary, only: :append_to_dark_time

  # 生成AIの濫用・コスト対策。ユーザーごとに一定時間内の生成回数を制限する。
  rate_limit to: 5, within: 1.hour,
             by: -> { current_user.id },
             with: -> { redirect_to regret_records_path, alert: t("regret_summaries.flash_message.rate_limited") },
             only: :generate

  # お気に入りの記録から要約を生成し、ユーザーの RegretSummary（1件）へ保存する（同期）。
  def generate
    content = RegretSummarizer.new(current_user).call
    @regret_summary = current_user.regret_summary || current_user.build_regret_summary
    @regret_summary.update!(content: content, generated_at: Time.current)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to regret_records_path, notice: t("regret_summaries.flash_message.generated") }
    end
  rescue RegretSummarizer::NoFavoritesError
    redirect_to regret_records_path, alert: t("regret_summaries.flash_message.no_favorites")
  rescue RegretSummarizer::GenerationError
    redirect_to regret_records_path, alert: t("regret_summaries.flash_message.generation_failed")
  end

  # 生成済みの要約を闇の時間の特徴（DarkTime#characteristic）へ追記する。
  def append_to_dark_time
    dark_time = current_user.dark_time
    if dark_time.nil?
      redirect_to regret_records_path, alert: t("regret_summaries.flash_message.dark_time_not_found")
      return
    end

    dark_time.merge_summary!(@regret_summary.content)
    redirect_to regret_records_path, notice: t("regret_summaries.flash_message.appended")
  end

  private

  def set_regret_summary
    @regret_summary = current_user.regret_summary
    return if @regret_summary

    redirect_to regret_records_path, alert: t("regret_summaries.flash_message.summary_not_found")
  end
end

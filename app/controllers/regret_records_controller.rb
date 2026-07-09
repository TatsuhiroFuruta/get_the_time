class RegretRecordsController < ApplicationController
  before_action :set_regret_record, only: %i[show edit update destroy favorite]

  def index
    @q = current_user.regret_records.ransack(params[:q])
    @regret_records = @q.result.order(created_at: :desc).page(params[:page]).per(9)
  end

  def show; end

  def edit; end

  def update
    if @regret_record.update(regret_record_params)
      redirect_to @regret_record, notice: t("defaults.flash_message.updated", item: RegretRecord.model_name.human)
    else
      flash.now[:alert] = t("defaults.flash_message.not_updated", item: RegretRecord.model_name.human)
      render :edit, status: :unprocessable_entity
    end
  end

  def new
    @regret_record = current_user.regret_records.build
  end

  def create
    @regret_record = current_user.regret_records.build(regret_record_params)
    if @regret_record.save
      redirect_to regret_records_path, notice: t("defaults.flash_message.created", item: RegretRecord.model_name.human)
    else
      flash.now[:alert] = t("defaults.flash_message.not_created", item: RegretRecord.model_name.human)
      render :new, status: :unprocessable_entity
    end
  end

  def destroy
    @regret_record.destroy!
    redirect_to regret_records_path, notice: t("defaults.flash_message.deleted", item: RegretRecord.model_name.human), status: :see_other
  end

  def favorite
    @regret_record.update!(favorited: !@regret_record.favorited)

    respond_to do |format|
      format.turbo_stream
      format.html { redirect_to regret_records_path }
    end
  end

  private

  def not_found_redirect_path
    regret_records_path
  end

  def set_regret_record
    @regret_record = current_user.regret_records.find(params[:id])
  end

  def regret_record_params
    params.require(:regret_record).permit(:title, :content)
  end
end

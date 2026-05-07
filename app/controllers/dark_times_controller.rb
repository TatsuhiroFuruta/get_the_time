class DarkTimesController < ApplicationController
  before_action :set_dark_time, only: %i[show edit update]
  before_action :redirect_if_dark_time_exists, only: %i[new create]
  before_action :redirect_if_dark_time_missing, only: %i[edit]

  def new
    @dark_time = current_user.build_dark_time
  end

  def create
    @dark_time = current_user.build_dark_time(dark_time_params)
    if @dark_time.save
      redirect_to mypage_path, notice: t('defaults.flash_message.created', item: DarkTime.model_name.human)
    else
      flash.now[:alert] = t('defaults.flash_message.not_created', item: DarkTime.model_name.human)
      render :new, status: :unprocessable_entity
    end
  end

  def show; end

  def edit; end

  def update
    if @dark_time.update(dark_time_params)
      redirect_to dark_time_path, notice: t('defaults.flash_message.updated', item: DarkTime.model_name.human)
    else
      flash.now[:alert] = t('defaults.flash_message.not_updated', item: DarkTime.model_name.human)
      render :edit, status: :unprocessable_entity
    end
  end

  private

  def set_dark_time
    @dark_time = current_user.dark_time
  end

  # 既に DarkTime が存在する場合は edit にリダイレクト
  def redirect_if_dark_time_exists
    return unless current_user.dark_time.present?

    redirect_to edit_dark_time_path, alert: t('defaults.flash_message.already_exists', item: DarkTime.model_name.human)
  end

  # DarkTime が存在しない場合は new にリダイレクト
  def redirect_if_dark_time_missing
    return if current_user.dark_time.present?

    redirect_to new_dark_time_path, alert: t('defaults.flash_message.not_found', item: DarkTime.model_name.human)
  end

  def dark_time_params
    params.require(:dark_time).permit(:behavior, :unwanted_future, :characteristic)
  end
end

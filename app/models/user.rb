class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :name, presence: true, length: { maximum: 30 }

  validates :password, format: { without: /\s/, message: "にスペースを含めることはできません" }, if: :password_required?

  has_one :dark_time, dependent: :destroy
  has_many :light_times, dependent: :destroy
  has_many :activity_records, dependent: :destroy
  has_one :purification_time, dependent: :destroy
  has_one :pomodoro_setting, dependent: :destroy
  has_many :regret_records, dependent: :destroy
  has_one :regret_summary, dependent: :destroy

  after_create :create_pomodoro_setting

  # Devise のメール（パスワード再設定等）を同期送信する。
  # 本番にバックグラウンドワーカー（Solid Queue）を常駐させなくても
  # 確実にメールが届くよう、deliver_later ではなく deliver_now を使う。
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_now
  end
end

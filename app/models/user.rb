class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable,
         :omniauthable, omniauth_providers: [ :google_oauth2 ]

  # 利用規約・プライバシーポリシーへの同意（DB カラムを持たない仮想属性）。
  # メール+パスワード登録フォームのチェックボックスから受け取り、新規登録時のみ必須。
  # on: :create に限定しているため、既存ユーザーの各種更新や OmniAuth 経由の作成
  # （agreement が nil のときバリデータはスキップ）には影響しない。
  attr_accessor :agreement
  validates :agreement, acceptance: { message: "に同意してください" }, on: :create

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

  # OmniAuth（Google）認証情報からユーザーを取得・作成する。
  # 検索は次の二段構えで行う:
  #   1. provider/uid（不変かつ一意な外部アカウントの正体）で既存ユーザーを探す。
  #      Google 側でメールが変更・再割り当てされても同一ユーザーを追従できる。
  #   2. 見つからなければメールアドレスで探す。既存のメール+パスワード登録ユーザーが
  #      いれば、そのアカウントに Google を紐付ける。
  # どちらでも見つからなければ新規作成し、その場合のみランダムパスワードを設定する
  # （既存ユーザーのパスワードは上書きしない）。
  def self.from_omniauth(auth)
    user = find_by(provider: auth.provider, uid: auth.uid) ||
           find_or_initialize_by(email: auth.info.email)
    user.provider = auth.provider
    user.uid = auth.uid
    user.name = auth.info.name if user.name.blank?
    user.password = Devise.friendly_token[0, 20] if user.new_record?
    user.save
    user
  end

  # Devise のメール（パスワード再設定等）を同期送信する。
  # 本番にバックグラウンドワーカー（Solid Queue）を常駐させなくても
  # 確実にメールが届くよう、deliver_later ではなく deliver_now を使う。
  def send_devise_notification(notification, *args)
    devise_mailer.send(notification, self, *args).deliver_now
  end
end

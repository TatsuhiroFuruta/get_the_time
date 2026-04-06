class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :name, presence: true, length: { maximum: 30 }

  has_one :dark_time, dependent: :destroy
  has_many :light_times, dependent: :destroy
  has_many :activity_records, dependent: :destroy
  has_one :purification_time, dependent: :destroy

  enum :current_mode, { idle: 0, purification: 1, activity: 2 }

  def can_start_purification?
    idle?
  end

  def can_start_activity?
    idle?
  end
end

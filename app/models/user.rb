class User < ApplicationRecord
  # Include default devise modules. Others available are:
  # :confirmable, :lockable, :timeoutable, :trackable and :omniauthable
  devise :database_authenticatable, :registerable,
         :recoverable, :rememberable, :validatable

  validates :name, presence: true, length: { maximum: 30 }

  validates :password, format: { without: /\s/, message: 'にスペースを含めることはできません' }, if: :password_required?

  has_one :dark_time, dependent: :destroy
  has_many :light_times, dependent: :destroy
  has_many :activity_records, dependent: :destroy
  has_one :purification_time, dependent: :destroy
end

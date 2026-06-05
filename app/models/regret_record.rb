class RegretRecord < ApplicationRecord
  validates :content, presence: true

  belongs_to :user

  # 検索可能カラムの登録（お気に入り絞り込み用）
  def self.ransackable_attributes(auth_object = nil)
    [ "favorited" ]
  end

  def self.ransackable_associations(auth_object = nil)
    []
  end
end

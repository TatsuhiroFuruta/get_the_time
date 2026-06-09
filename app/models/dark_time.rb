class DarkTime < ApplicationRecord
  # 生成AI要約を characteristic に差し込む際の区切り見出し
  SUMMARY_HEADING = "【AIによる後悔の傾向まとめ】".freeze

  validates :behavior, presence: true
  validates :user_id, uniqueness: true

  belongs_to :user

  # 要約を「区切り見出し」ブロックとして characteristic へ反映する。
  # 既存の見出しブロックがあれば差し替え、無ければ末尾に追記する（手入力分は温存）。
  # 見出しブロックは常に末尾に置かれる前提で、見出し以降〜末尾を対象に置換する。
  def merge_summary!(summary)
    block = "#{SUMMARY_HEADING}\n#{summary.to_s.strip}"
    existing = characteristic.to_s
    heading_to_end = /#{Regexp.escape(SUMMARY_HEADING)}.*\z/m

    new_value =
      if existing.match?(heading_to_end)
        existing.sub(heading_to_end, block)
      elsif existing.strip.empty?
        block
      else
        "#{existing.rstrip}\n\n#{block}"
      end

    update!(characteristic: new_value)
  end
end

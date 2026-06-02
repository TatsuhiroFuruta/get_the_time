module ActivityRecordsHelper
  # 今日の本来の自分(0..1)を6段階レベル(0..5)へ変換する。
  #   0: 未計測 または 0%（光なし） / 1: 0%超〜20%未満 / 2: 20%〜40%未満
  #   3: 40%〜60%未満 / 4: 60%〜80%未満 / 5: 80%〜100%
  def desired_self_level(percentage)
    return 0 if percentage.blank?

    pct = percentage.to_f * 100
    case pct
    when 0 then 0
    when 0...20 then 1
    when 20...40 then 2
    when 40...60 then 3
    when 60...80 then 4
    else 5
    end
  end

  # レベルに対応する背景画像のパス。画像が未配置のときは nil（フォールバック表示に切り替える）
  def desired_self_image_path(level)
    return nil if level.nil?

    logical_path = "desired_self/level_#{level}.png"
    return nil unless Rails.application.assets.load_path.find(logical_path)

    image_path(logical_path)
  end

  # 画像未配置・未計測時に使うレンジ別フォールバック用グラデーションクラス
  def desired_self_fallback_class(level)
    case level
    when 0 then "bg-linear-to-br from-slate-700 to-slate-900"
    when 1 then "bg-linear-to-br from-slate-500 to-slate-700"
    when 2 then "bg-linear-to-br from-indigo-400 to-indigo-700"
    when 3 then "bg-linear-to-br from-sky-300 to-sky-600"
    when 4 then "bg-linear-to-br from-amber-300 to-amber-500"
    when 5 then "bg-linear-to-br from-yellow-200 to-amber-400"
    else "bg-linear-to-br from-gray-300 to-gray-500"
    end
  end

  # 一覧カードのテキスト省略ルール
  #   未記入のとき → "..."
  #   10文字超のとき → 先頭10文字 + "..."
  def truncate_card_text(text)
    return "..." if text.blank?

    text.length > 10 ? "#{text.first(10)}..." : text
  end

  def rating_field(form, field, label, left_label:, right_label:)
    content_tag(:div, class: "mb-6") do
      concat content_tag(:p, label, class: "mb-2 font-semibold")

      # 上の数字（1〜5）
      concat(
        content_tag(:div, class: "grid grid-cols-7 text-center mb-1") do
          ([ "" ] + (1..5).to_a + [ "" ]).map do |i|
            content_tag(:div, i, class: "text-sm text")
          end.join.html_safe
        end
      )

      # ラジオボタン列
      concat(
        content_tag(:div, class: "grid grid-cols-7 items-center text-center") do
          elements = []

          # 左ラベル
          elements << content_tag(:div, left_label, class: "text-sm")

          # ラジオボタン
          (1..5).each do |i|
            elements << content_tag(:label, class: "cursor-pointer") do
              form.radio_button(field, i)
            end
          end

          # 右ラベル
          elements << content_tag(:div, right_label, class: "text-sm")

          elements.join.html_safe
        end
      )
    end
  end
end

module ActivityRecordsHelper
  def rating_field(form, field, label, left_label:, right_label:)
    content_tag(:div, class: "mb-6") do
      concat content_tag(:p, label, class: "mb-2 font-semibold")

      # 上の数字（1〜5）
      concat(
        content_tag(:div, class: "grid grid-cols-7 text-center mb-1") do
          ([""] + (1..5).to_a + [""]).map do |i|
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

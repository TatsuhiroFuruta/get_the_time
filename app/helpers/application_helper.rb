module ApplicationHelper
  # ブラウザタイトルのサービス名（接尾辞）
  SITE_TITLE = "Get The Time"

  # サービスの紹介文（OGP / PWA manifest 等のメタデータで共用）
  SITE_DESCRIPTION = "自由時間を「光の時間」と「闇の時間」に分け、本来の自分を計測するサービス"

  # 任意入力フィールドのラベル接尾辞
  OPTIONAL_LABEL_SUFFIX = "（任意）"

  # ビュー（ERB）から定数を安全に参照するためのアクセサ。
  # ERB テンプレート内の裸の定数は字句スコープの都合で解決されないため、
  # メタデータ用途ではこれらのヘルパー経由で取得する。
  def site_title
    SITE_TITLE
  end

  def site_description
    SITE_DESCRIPTION
  end

  # <title> の文言を組み立てる。
  # 各ビューで content_for(:title, ...) が設定されていれば
  # 「ページ名 | Get The Time」、無ければサービス名のみを返す。
  def page_title
    page = content_for(:title)
    page.present? ? "#{page} | #{SITE_TITLE}" : SITE_TITLE
  end

  # 「（任意）」付きのフォームラベルを生成する。
  # ラベル名は i18n（activerecord/activemodel の attributes）から引くため、
  # 属性名そのものはクリーンに保たれ、エラーメッセージには「（任意）」が混入しない。
  def optional_label(form, attribute, **options)
    label_text = "#{form.object.class.human_attribute_name(attribute)}#{OPTIONAL_LABEL_SUFFIX}"
    form.label(attribute, label_text, **options)
  end

  def format_datetime(dt)
    dt&.in_time_zone("Tokyo")&.strftime("%Y-%m-%d %H:%M")
  end

  def format_seconds_to_mmss(elapsed_seconds)
    minutes = elapsed_seconds / 60
    seconds = elapsed_seconds % 60
    "#{minutes} 分 #{seconds.to_s.rjust(2, "0")} 秒"
  end

  def format_minutes_to_hm(elapsed_minutes)
    hours = elapsed_minutes / 60
    minutes = elapsed_minutes % 60
    "#{hours} 時間 #{minutes.to_s.rjust(2, "0")} 分"
  end

  def display_percentage(value)
    return nil if value.blank?

    "#{(value * 100).round(1)} %"
  end

  def nav_link_class(path)
    base = "block py-2 text-center border-t border-amber-500"
    active = "bg-linear-to-b from-yellow-200 from-0% via-yellow-300 via-80% to-yellow-600 to-100%"
    inactive = "bg-yellow-200"

    is_active = current_page?(path) || (path == mypage_path && current_page?(root_path))

    "#{base} #{is_active ? active : inactive}"
  end
end

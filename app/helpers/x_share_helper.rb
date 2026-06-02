module XShareHelper
  # X（Twitter）の投稿画面 Web Intent。テキストのみ渡せる（画像は添付不可）
  X_INTENT_URL = "https://twitter.com/intent/tweet".freeze

  # ハッシュタグ（# は付けない。X 側が自動付与する）
  SERVICE_HASHTAG   = "GetTheTime".freeze
  OVERALL_HASHTAGS  = [ SERVICE_HASHTAG, "本来の自分" ].freeze       # 本来の自分（平均）向け
  ACTIVITY_HASHTAGS = [ SERVICE_HASHTAG, "今日の本来の自分" ].freeze # 今日の本来の自分（活動記録）向け

  # 「本来の自分」シェア文面（マイステータスの平均向け）
  #   例: 「2026年6月2日の本来の自分は 89.0 % です」
  #   パーセント表記は共通の display_percentage に委譲（呼び出し側で present? を担保済み）
  def x_share_overall_text(percentage, date: Time.current)
    "#{format_date_ja(date)}の本来の自分は #{display_percentage(percentage)} です"
  end

  # 「今日の本来の自分」シェア文面（活動記録向け）
  #   例: 「2026年6月2日14時30分開始の活動における今日の本来の自分は 89.0 % です」
  def x_share_activity_text(percentage, started_at:)
    "#{format_date_ja(started_at)}#{format_time_ja(started_at)}開始の活動における今日の本来の自分は #{display_percentage(percentage)} です"
  end

  # 投稿本文を「本文 → ハッシュタグ → URL」の順に改行で組み立てる。
  # 並び順を X 任せにせずこちらで確定させるため、URL もハッシュタグも text に含める。
  def x_share_message(body, hashtags: nil, url: nil)
    hashtag_line = Array(hashtags).map { |tag| "##{tag}" }.join(" ")
    [ body, hashtag_line, url ].reject(&:blank?).join("\n")
  end

  # X 投稿画面の URL。並び順を確定させた本文を text にまとめて載せる
  def x_intent_url(text)
    "#{X_INTENT_URL}?#{{ text: text }.to_query}"
  end

  # 日本語の日付表記（JST）。例: "2026年6月2日"
  def format_date_ja(time)
    time.in_time_zone("Tokyo").strftime("%Y年%-m月%-d日")
  end

  # 日本語の時刻表記（JST）。例: "14時30分"
  def format_time_ja(time)
    time.in_time_zone("Tokyo").strftime("%-H時%-M分")
  end
end

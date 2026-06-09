# お気に入り登録された「後悔した1日」の記録を生成AI（OpenAI）で要約するサービス。
#
# 書き込み経路をオブジェクトに集約する流儀（app/forms/activity_record_form.rb）に倣い、
# OpenAI 呼び出しの組み立て・入力制限・エラー変換をここに閉じ込める。
#
# 入力はお気に入り（favorited: true）の記録のみ。トークン上限の保険として
# 件数 MAX_RECORDS・1件あたり MAX_CHARS_PER_RECORD 文字でハードキャップする。
class RegretSummarizer
  MAX_RECORDS = 30                # 要約対象に含めるお気に入り記録の最大件数
  MAX_CHARS_PER_RECORD = 300      # 1件あたりプロンプトに渡す最大文字数
  MODEL = "gpt-4o-mini"

  # お気に入りが0件のときに投げる（コントローラ側でガード文言に変換）
  class NoFavoritesError < StandardError; end
  # API 呼び出し失敗・空応答のときに投げる（コントローラ側で失敗文言に変換）
  class GenerationError < StandardError; end

  def initialize(user)
    @user = user
  end

  # 要約テキスト（String）を返す。失敗時は上記の例外を投げる。
  def call
    records = favorited_records
    raise NoFavoritesError if records.empty?

    response = client.chat(parameters: chat_parameters(records))
    content = response.dig("choices", 0, "message", "content").to_s.strip
    raise GenerationError, "要約結果が空でした" if content.blank?

    content
  rescue Faraday::Error => e
    raise GenerationError, e.message
  end

  private

  attr_reader :user

  def favorited_records
    user.regret_records.where(favorited: true).order(created_at: :desc).limit(MAX_RECORDS)
  end

  def client
    @client ||= OpenAI::Client.new
  end

  def chat_parameters(records)
    {
      model: MODEL,
      temperature: 0.3,
      messages: [
        { role: "system", content: system_prompt },
        { role: "user", content: user_prompt(records) }
      ]
    }
  end

  def system_prompt
    <<~PROMPT.strip
      あなたはユーザーの自己理解を助けるコーチです。
      ユーザーが「後悔した1日」として記録した内容をもとに、
      その人が誘惑に流されてしまう傾向（闇の時間の特徴）を、本人が自己認識を深められるように要約してください。

      制約:
      - 日本語で、200文字以内にまとめること。
      - 個人を特定しうる固有名詞や記録の文面をそのまま反芻しないこと。
      - 傾向・パターンとして一般化し、責めるのではなく気づきを促す前向きな言葉で書くこと。
      - 箇条書きではなく、地の文で簡潔にまとめること。
      - 医学的・心理的な診断や病名の言及はせず、断定を避けて気づきを促す表現にとどめること。
    PROMPT
  end

  def user_prompt(records)
    list = records.map.with_index(1) do |record, index|
      "#{index}. #{record.content.to_s.truncate(MAX_CHARS_PER_RECORD)}"
    end.join("\n")

    <<~PROMPT.strip
      以下は、ユーザーが後悔した1日として記録した内容の一覧です。
      この人が闇の時間（誘惑に費やしてしまう時間）に陥りやすい傾向を要約してください。

      #{list}
    PROMPT
  end
end

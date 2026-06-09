require "rails_helper"

RSpec.describe RegretSummarizer do
  let(:user) { create(:user) }
  let(:chat_response) { { "choices" => [ { "message" => { "content" => "誘惑に流されやすい傾向の要約" } } ] } }
  let(:client) { instance_double(OpenAI::Client) }

  before do
    allow(OpenAI::Client).to receive(:new).and_return(client)
    allow(client).to receive(:chat).and_return(chat_response)
  end

  # チャットに渡された user プロンプト本文を取り出すヘルパ
  def captured_user_prompt
    args = nil
    expect(client).to have_received(:chat) { |a| args = a }
    args[:parameters][:messages].last[:content]
  end

  # チャットに渡された system プロンプト本文を取り出すヘルパ
  def captured_system_prompt
    args = nil
    expect(client).to have_received(:chat) { |a| args = a }
    args[:parameters][:messages].first[:content]
  end

  describe "#call" do
    it "OpenAI の応答テキストを返すこと" do
      create(:regret_record, user: user, favorited: true)

      expect(RegretSummarizer.new(user).call).to eq("誘惑に流されやすい傾向の要約")
    end

    it "お気に入りの記録のみをプロンプトに含めること（非お気に入り・他ユーザーを含めない）" do
      create(:regret_record, user: user, favorited: true, content: "お気に入りの後悔")
      create(:regret_record, user: user, favorited: false, content: "通常の後悔")
      create(:regret_record, user: create(:user), favorited: true, content: "他人の後悔")

      RegretSummarizer.new(user).call

      prompt = captured_user_prompt
      aggregate_failures do
        expect(prompt).to include("お気に入りの後悔")
        expect(prompt).not_to include("通常の後悔")
        expect(prompt).not_to include("他人の後悔")
      end
    end

    it "件数が MAX_RECORDS を超えても上限までしか含めないこと" do
      (RegretSummarizer::MAX_RECORDS + 5).times do |i|
        create(:regret_record, user: user, favorited: true, content: "後悔#{i}")
      end

      RegretSummarizer.new(user).call

      numbered_lines = captured_user_prompt.scan(/^\d+\. /)
      expect(numbered_lines.size).to eq(RegretSummarizer::MAX_RECORDS)
    end

    it "ちょうど MAX_RECORDS 件のときは全件含めること" do
      RegretSummarizer::MAX_RECORDS.times do |i|
        create(:regret_record, user: user, favorited: true, content: "後悔#{i}")
      end

      RegretSummarizer.new(user).call

      numbered_lines = captured_user_prompt.scan(/^\d+\. /)
      expect(numbered_lines.size).to eq(RegretSummarizer::MAX_RECORDS)
    end

    it "1件あたり MAX_CHARS_PER_RECORD を超える内容は切り詰めること" do
      long_content = "あ" * 400
      create(:regret_record, user: user, favorited: true, content: long_content)

      RegretSummarizer.new(user).call

      expect(captured_user_prompt).not_to include(long_content)
    end

    it "ちょうど MAX_CHARS_PER_RECORD 文字の内容は切り詰めないこと" do
      exact_content = "あ" * RegretSummarizer::MAX_CHARS_PER_RECORD
      create(:regret_record, user: user, favorited: true, content: exact_content)

      RegretSummarizer.new(user).call

      expect(captured_user_prompt).to include(exact_content)
    end

    it "システムプロンプトに診断・断定を避ける指示を含めること" do
      create(:regret_record, user: user, favorited: true)

      RegretSummarizer.new(user).call

      aggregate_failures do
        expect(captured_system_prompt).to include("診断")
        expect(captured_system_prompt).to include("断定を避け")
      end
    end

    it "お気に入りが0件のときは NoFavoritesError を投げること" do
      create(:regret_record, user: user, favorited: false)

      expect { RegretSummarizer.new(user).call }.to raise_error(RegretSummarizer::NoFavoritesError)
    end

    it "API 呼び出しが失敗したときは GenerationError に変換すること" do
      create(:regret_record, user: user, favorited: true)
      allow(client).to receive(:chat).and_raise(Faraday::ConnectionFailed.new("boom"))

      expect { RegretSummarizer.new(user).call }.to raise_error(RegretSummarizer::GenerationError)
    end

    it "応答が空のときは GenerationError を投げること" do
      create(:regret_record, user: user, favorited: true)
      allow(client).to receive(:chat).and_return({ "choices" => [ { "message" => { "content" => "" } } ] })

      expect { RegretSummarizer.new(user).call }.to raise_error(RegretSummarizer::GenerationError)
    end
  end
end

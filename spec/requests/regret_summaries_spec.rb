require "rails_helper"

RSpec.describe "RegretSummaries", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "PATCH /regret_summary/generate" do
    let(:summary_text) { "誘惑に流されやすい傾向の要約" }
    let(:summarizer) { instance_double(RegretSummarizer, call: summary_text) }

    before do
      allow(RegretSummarizer).to receive(:new).and_return(summarizer)
    end

    context "正常系" do
      it "RegretSummary が作成されること" do
        aggregate_failures do
          expect {
            patch generate_regret_summary_path
          }.to change { user.reload.regret_summary }.from(nil)

          expect(user.regret_summary.content).to eq(summary_text)
        end
      end

      it "既存の要約があるときは内容が更新されること" do
        create(:regret_summary, user: user, content: "古い要約")

        patch generate_regret_summary_path

        expect(user.regret_summary.reload.content).to eq(summary_text)
      end

      it "turbo_stream リクエストで 200 を返すこと" do
        patch generate_regret_summary_path, headers: { "Accept" => "text/vnd.turbo-stream.html" }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end
      end

      it "html リクエストで一覧ページへリダイレクトすること" do
        patch generate_regret_summary_path

        aggregate_failures do
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:notice]).to eq(I18n.t("regret_summaries.flash_message.generated"))
        end
      end
    end

    context "お気に入りが0件のとき" do
      before do
        allow(summarizer).to receive(:call).and_raise(RegretSummarizer::NoFavoritesError)
      end

      it "要約は作られず alert つきでリダイレクトすること" do
        aggregate_failures do
          expect { patch generate_regret_summary_path }.not_to change(RegretSummary, :count)
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:alert]).to eq(I18n.t("regret_summaries.flash_message.no_favorites"))
        end
      end
    end

    context "生成に失敗したとき" do
      before do
        allow(summarizer).to receive(:call).and_raise(RegretSummarizer::GenerationError)
      end

      it "alert つきでリダイレクトすること" do
        aggregate_failures do
          expect { patch generate_regret_summary_path }.not_to change(RegretSummary, :count)
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:alert]).to eq(I18n.t("regret_summaries.flash_message.generation_failed"))
        end
      end
    end
  end

  describe "PATCH /regret_summary/append_to_dark_time" do
    context "要約と闇の時間がそろっているとき" do
      let!(:regret_summary) { create(:regret_summary, user: user, content: "夜更かしの傾向がある") }
      let!(:dark_time) { create(:dark_time, user: user, characteristic: "意志が弱い") }

      it "闇の時間の特徴へ見出しブロックが追記され、一覧へリダイレクトすること" do
        patch append_to_dark_time_regret_summary_path

        aggregate_failures do
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:notice]).to eq(I18n.t("regret_summaries.flash_message.appended"))
          characteristic = dark_time.reload.characteristic
          expect(characteristic).to include("意志が弱い")
          expect(characteristic).to include("#{DarkTime::SUMMARY_HEADING}\n夜更かしの傾向がある")
        end
      end
    end

    context "闇の時間が未登録のとき" do
      let!(:regret_summary) { create(:regret_summary, user: user) }

      it "alert つきでリダイレクトすること" do
        patch append_to_dark_time_regret_summary_path

        aggregate_failures do
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:alert]).to eq(I18n.t("regret_summaries.flash_message.dark_time_not_found"))
        end
      end
    end

    context "要約が未生成のとき" do
      let!(:dark_time) { create(:dark_time, user: user, characteristic: "意志が弱い") }

      it "闇の時間は変更されず alert つきでリダイレクトすること" do
        patch append_to_dark_time_regret_summary_path

        aggregate_failures do
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:alert]).to eq(I18n.t("regret_summaries.flash_message.summary_not_found"))
          expect(dark_time.reload.characteristic).to eq("意志が弱い")
        end
      end
    end
  end
end

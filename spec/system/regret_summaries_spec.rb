require "rails_helper"

RSpec.describe "RegretSummaries", type: :system do
  let(:user) { create(:user) }
  # ハンバーガーメニューはマイページに dark_time と light_time の両方がある時のみ表示される
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user, characteristic: "意志が弱い") }

  before do
    sign_in user
  end

  describe "要約の生成と追記" do
    let(:summary_text) { "誘惑に流されやすく、夜更かしと動画視聴に時間を奪われる傾向がある。" }

    before do
      # OpenAI を呼ばないよう、サービス境界をスタブする（system spec はアプリと同一プロセス）
      allow_any_instance_of(RegretSummarizer).to receive(:call).and_return(summary_text)
    end

    context "お気に入りの記録があるとき" do
      let!(:regret_record) { create(:regret_record, user: user, favorited: true, content: "一日中スマホを触ってしまった") }

      it "要約を生成して表示し、闇の時間の特徴へ追記できること" do
        visit regret_records_path

        # 要約対象の件数上限が案内されている
        expect(page).to have_content("最新#{RegretSummarizer::MAX_RECORDS}件")

        click_on "要約する"

        # 要約パネルに生成結果と追記ボタンが表示される
        aggregate_failures do
          expect(page).to have_content(summary_text)
          expect(page).to have_button("闇の時間の特徴へ追記する")
        end

        click_on "闇の時間の特徴へ追記する"

        aggregate_failures do
          expect(page).to have_current_path(regret_records_path)
          expect(page).to have_content(I18n.t("regret_summaries.flash_message.appended"))
        end

        # 闇の時間の特徴詳細に、手入力分を残しつつ要約が反映されている
        visit dark_time_path
        aggregate_failures do
          expect(page).to have_content("意志が弱い")
          expect(page).to have_content(DarkTime::SUMMARY_HEADING)
          expect(page).to have_content(summary_text)
        end
      end
    end

    context "お気に入りの記録が1件もないとき" do
      let!(:regret_record) { create(:regret_record, user: user, favorited: false) }

      it "要約ボタンが表示されず、案内文が表示されること" do
        visit regret_records_path

        aggregate_failures do
          expect(page).not_to have_button("要約する")
          expect(page).to have_content("★お気に入りに登録すると要約できます")
        end
      end
    end
  end
end

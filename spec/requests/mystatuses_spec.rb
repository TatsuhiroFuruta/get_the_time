require "rails_helper"

RSpec.describe "Mystatuses", type: :request do
  let(:user) { create(:user) }
  let(:light_time) { create(:light_time, :current, user: user) }

  describe "GET /mystatus" do
    context "ログイン済みのとき" do
      before { sign_in user }

      it "200 が返り、タイトルが表示されること" do
        get mystatus_path

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("マイステータス")
        end
      end

      it "活動記録が存在しても 200 が返ること" do
        create(:activity_record, user: user)

        get mystatus_path

        expect(response).to have_http_status(:ok)
      end

      it "活動記録のない日は light_time の data 属性が 30 個の 0 配列として埋め込まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          get mystatus_path
        end

        expected_array = "[#{Array.new(30, 0).join(",")}]"
        expect(response.body).to include(%(data-mystatus-chart-data-value="#{expected_array}"))
      end

      it "活動記録がある日は light_time の data 属性に合計分数が含まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          create(:activity_record, user: user, light_time: light_time,
                                   total_duration: 90, idle_duration: 10)

          get mystatus_path
        end

        # 30日分の末尾（=本日）に 90 が入る
        expected_array = "[#{(Array.new(29, 0) + [ 90 ]).join(",")}]"
        expect(response.body).to include(%(data-mystatus-chart-data-value="#{expected_array}"))
      end

      it "本来の自分の data 属性に desired_self_percentage が % 単位で含まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          # (90 - 10) / 90 ≒ 0.8888... → DB の decimal(5,2) で 0.89 に丸め → *100 で 89.0
          create(:activity_record, user: user, light_time: light_time,
                                   total_duration: 90, idle_duration: 10)

          get mystatus_path
        end

        # 本来の自分のチャート用 data 属性に 89.0 が含まれる（記録のない日は null）
        expect(response.body).to match(/data-mystatus-chart-data-value="\[[^"]*89\.0\]"/)
      end
    end

    context "未ログインのとき" do
      it "ログインページへリダイレクトされること" do
        get mystatus_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end
end

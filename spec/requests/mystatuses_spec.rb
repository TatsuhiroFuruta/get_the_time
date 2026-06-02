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

      it "活動記録のない日は light_time の data 属性が 14 個の 0 配列として埋め込まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          get mystatus_path
        end

        expected_array = "[#{Array.new(14, 0).join(",")}]"
        expect(response.body).to include(%(data-mystatus-chart-data-value="#{expected_array}"))
      end

      it "活動記録がある日は light_time の data 属性に合計分数が含まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          create(:activity_record, user: user, light_time: light_time,
                                   total_duration: 90, idle_duration: 10)

          get mystatus_path
        end

        # 14日分の末尾（=本日）に 90 が入る
        expected_array = "[#{(Array.new(13, 0) + [ 90 ]).join(",")}]"
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

      it "本来の自分の14日平均がパーセント表記で大きく表示されること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          # (90 - 10) / 90 → decimal(5,2) で 0.89 → display_percentage で「89.0 %」
          create(:activity_record, user: user, light_time: light_time,
                                   total_duration: 90, idle_duration: 10)

          get mystatus_path
        end

        aggregate_failures do
          expect(response.body).to include("本来の自分（直近14日平均）")
          expect(response.body).to include("89.0 %")
        end
      end

      it "平均が存在するとき X 投稿画面へのリンクと文面が描画されること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          create(:activity_record, user: user, light_time: light_time,
                                   total_duration: 90, idle_duration: 10)

          get mystatus_path
        end

        aggregate_failures do
          expect(response.body).to include("twitter.com/intent/tweet")
          expect(response.body).to include(CGI.escape("2026年5月30日の本来の自分は 89.0 % です"))
          expect(response.body).to include(CGI.escape("#GetTheTime #本来の自分"))
        end
      end

      it "記録がなく平均が無いときは X シェアボタンを描画しないこと" do
        get mystatus_path
        expect(response.body).not_to include("twitter.com/intent/tweet")
      end

      it "評価レーダーの data 属性に4項目の平均値が含まれること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          create(:activity_record, user: user, light_time: light_time,
                                   satisfaction: 4, progress: 4, quality: 4, focus: 4, fatigue: 2)

          get mystatus_path
        end

        # 満足度・進行度・作業の質・集中度の順に平均値（ここでは全て 4.0）
        expect(response.body).to include(%(data-mystatus-radar-chart-data-value="[4.0,4.0,4.0,4.0]"))
      end

      it "疲労感が逆指標である旨と平均値が表示されること" do
        travel_to Time.zone.local(2026, 5, 30, 12, 0, 0) do
          create(:activity_record, user: user, light_time: light_time, fatigue: 2)

          get mystatus_path
        end

        aggregate_failures do
          expect(response.body).to include("疲労感（低いほど良い）")
          expect(response.body).to include("2.0 / 5")
        end
      end

      it "評価データがない場合はレーダーの代わりに案内文が表示されること" do
        get mystatus_path

        aggregate_failures do
          expect(response.body).to include("まだ評価データがありません")
          expect(response.body).not_to include("data-mystatus-radar-chart-data-value")
        end
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

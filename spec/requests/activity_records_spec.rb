require "rails_helper"

RSpec.describe "ActivityRecords", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let(:other_light_time) { create(:light_time, :current, user: other_user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before { sign_in user }

  # =========================================================
  # GET /activity_records (index)
  # =========================================================
  describe "GET /activity_records" do
    it "200 を返すこと" do
      get activity_records_path
      expect(response).to have_http_status(:ok)
    end

    context "未ログインのとき" do
      before { sign_out user }

      it "ログインページへリダイレクトすること" do
        get activity_records_path
        expect(response).to redirect_to(new_user_session_path)

        follow_redirect!
        expect(response.body).to include(
          I18n.t("devise.failure.unauthenticated")
        )
      end
    end

    context "自分と他ユーザーの活動記録があるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, comment: "自分のコメント")
        create(:activity_record, user: other_user, light_time: other_light_time, comment: "他人のコメント")
      end

      it "自分の活動記録のみが表示され、他ユーザーの活動記録は表示されないこと" do
        get activity_records_path

        aggregate_failures do
          expect(response.body).to include("自分のコメント")
          expect(response.body).not_to include("他人のコメント")
        end
      end
    end

    context "検索パラメータがあるとき" do
      before do
        create(:activity_record, user: user, light_time: light_time, comment: "マッチするコメント")
        create(:activity_record, user: user, light_time: light_time, comment: "ヒットしない")
      end

      it "200 を返すこと" do
        get activity_records_path, params: { q: { comment_or_light_time_action_cont: "マッチ" } }
        expect(response).to have_http_status(:ok)
      end
    end
  end

  # =========================================================
  # GET /activity_records/pomodoro_timer
  # =========================================================
  describe "GET /activity_records/pomodoro_timer" do
    it "200 を返すこと" do
      get pomodoro_timer_activity_records_path
      expect(response).to have_http_status(:ok)
    end

    context "task パラメータがあるとき" do
      it "レスポンスボディに task の内容が含まれること" do
        get pomodoro_timer_activity_records_path(task: "テストタスク")

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("テストタスク")
        end
      end
    end
  end

  # =========================================================
  # GET /activity_records/new
  # =========================================================
  describe "GET /activity_records/new" do
    let(:form_params) do
      {
        activity_record_form: {
          started_at:     1.hour.ago.iso8601,
          ended_at:       Time.current.iso8601,
          total_duration: 60,
          task:           "タスク",
          light_time_id:   light_time.id
        }
      }
    end

    context "activity_record_form パラメータがあるとき" do
      it "200 を返すこと" do
        get new_activity_record_path, params: form_params
        expect(response).to have_http_status(:ok)
      end
    end

    context "activity_record_form パラメータがないとき" do
      it "ポモドーロタイマーページへリダイレクトすること" do
        get new_activity_record_path
        aggregate_failures do
          expect(response).to redirect_to(pomodoro_timer_activity_records_path)
          expect(flash[:alert]).to eq(
            I18n.t("activity_records.flash_message.require_timer_access")
          )
        end
      end
    end
  end

  # =========================================================
  # POST /activity_records (create)
  # =========================================================
  describe "POST /activity_records" do
    let(:valid_params) do
      {
        activity_record_form: {
          started_at:                1.hour.ago.iso8601,
          ended_at:                  Time.current.iso8601,
          total_duration:            60,
          idle_duration:             5,
          satisfaction:              3,
          progress:                  3,
          quality:                   3,
          focus:                     3,
          fatigue:                   3,
          task:                      "テストタスク",
          light_time_id:             light_time.id,
          comment:                   "テストコメント",
          light_time_characteristic: "",
          dark_time_characteristic:  ""
        }
      }
    end

    let(:success_message) do
      I18n.t("defaults.flash_message.created", item: ActivityRecordForm.model_name.human)
    end

    let(:failure_message) do
      I18n.t("defaults.flash_message.not_created", item: ActivityRecordForm.model_name.human)
    end

    context "正常なパラメータのとき" do
      it "ActivityRecord が 1 件増えること" do
        expect { post activity_records_path, params: valid_params }
          .to change(ActivityRecord, :count).by(1)
      end

      it "一覧ページへリダイレクトし、成功メッセージがセットされること" do
        post activity_records_path, params: valid_params
        aggregate_failures do
          expect(response).to redirect_to(activity_records_path)
          expect(flash[:notice]).to eq(success_message)
        end
      end

      context "total_duration >= 30 のとき" do
        before { allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10) }

        it "flash[:purification_time] に付与メッセージがセットされること" do
          post activity_records_path, params: valid_params
          expect(flash[:purification_time]).to eq "浄化タイマーを20分獲得！"
        end
      end

      context "total_duration < 30 のとき" do
        before { valid_params[:activity_record_form][:total_duration] = 10 }

        it "flash[:purification_time] がセットされないこと" do
          post activity_records_path, params: valid_params
          expect(flash[:purification_time]).to be_nil
        end
      end

      # 付与計算が表示と保存で二重に走ると乱数で値がズレるため、
      # ブロックごとに異なる分数を返す系列でスタブして「表示＝保存」を保証する。
      context "付与分数が乱数で変動するとき（表示と保存の一致）" do
        before do
          # 60 分 = 2 ブロック。1 回しか計算しなければ 8 + 10 = 18 分が確定する。
          allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(8, 10)
        end

        it "フラッシュの分数と実際に付与された残り時間が一致すること" do
          post activity_records_path, params: valid_params

          aggregate_failures do
            expect(flash[:purification_time]).to eq "浄化タイマーを18分獲得！"
            expect(user.purification_time.remaining_time).to eq 18 * 60
          end
        end
      end
    end

    context "不正なパラメータのとき（satisfaction が範囲外）" do
      before { valid_params[:activity_record_form][:satisfaction] = 0 }

      it "ActivityRecord が増えないこと" do
        expect { post activity_records_path, params: valid_params }
          .not_to change(ActivityRecord, :count)
      end

      it "422 を返し、エラーメッセージがセットされること" do
        post activity_records_path, params: valid_params
        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(flash[:alert]).to eq(failure_message)
        end
      end
    end
  end

  # =========================================================
  # GET /activity_records/:id (show)
  # =========================================================
  describe "GET /activity_records/:id" do
    let(:activity_record) { create(:activity_record, user: user, light_time: light_time) }

    it "200 を返すこと" do
      get activity_record_path(activity_record)
      expect(response).to have_http_status(:ok)
    end

    it "他ユーザーのレコードにアクセスすると 404 を返すこと" do
      other_activity_record = create(:activity_record, user: other_user, light_time: other_light_time)

      get activity_record_path(other_activity_record)
      expect(response).to have_http_status(:not_found)
    end

    it "本来の自分が計測済みのとき X 投稿画面へのリンクと文面が描画されること" do
      record = create(:activity_record, user: user, light_time: light_time,
                                        started_at: Time.zone.local(2026, 6, 2, 14, 30),
                                        total_duration: 60, idle_duration: 30)

      get activity_record_path(record)

      expected_body = "2026年6月2日14時30分開始の約60分間の活動における今日の本来の自分は 50.0 % です"
      aggregate_failures do
        expect(response.body).to include("でシェア")
        expect(response.body).to include("twitter.com/intent/tweet")
        expect(response.body).to include(CGI.escape(expected_body))
        expect(response.body).to include(CGI.escape("#GetTheTime #今日の本来の自分"))
      end
    end
  end

  # =========================================================
  # GET /activity_records/:id/edit
  # =========================================================
  describe "GET /activity_records/:id/edit" do
    let(:activity_record) { create(:activity_record, user: user, light_time: light_time) }

    it "200 を返すこと" do
      get edit_activity_record_path(activity_record)
      expect(response).to have_http_status(:ok)
    end

    it "他ユーザーのレコードにアクセスすると 404 を返すこと" do
      other_activity_record = create(:activity_record, user: other_user, light_time: other_light_time)

      get edit_activity_record_path(other_activity_record)
      expect(response).to have_http_status(:not_found)
    end
  end

  # =========================================================
  # PATCH /activity_records/:id (update)
  # =========================================================
  describe "PATCH /activity_records/:id" do
    let(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, comment: "元のコメント")
    end

    let(:success_message) do
      I18n.t("defaults.flash_message.updated", item: ActivityRecord.model_name.human)
    end

    let(:failure_message) do
      I18n.t("defaults.flash_message.not_updated", item: ActivityRecord.model_name.human)
    end

    context "正常なパラメータのとき" do
      let(:update_params) do
        {
          activity_record: {
            idle_duration: 10,
            satisfaction:  5,
            progress:      4,
            quality:       4,
            focus:         5,
            fatigue:       2,
            comment:       "更新後のコメント"
          }
        }
      end

      it "詳細ページへリダイレクトし、成功メッセージがセットされること" do
        patch activity_record_path(activity_record), params: update_params
        aggregate_failures do
          expect(response).to redirect_to(activity_record_path(activity_record))
          expect(flash[:notice]).to eq(success_message)
        end
      end

      it "comment が更新されること" do
        patch activity_record_path(activity_record), params: update_params
        expect(activity_record.reload.comment).to eq "更新後のコメント"
      end
    end

    context "不正なパラメータのとき（idle_duration > total_duration）" do
      let(:bad_params) do
        {
          activity_record: {
            idle_duration: 9999,
            satisfaction:  3, progress: 3, quality: 3, focus: 3, fatigue: 3
          }
        }
      end

      it "422 を返し、エラーメッセージがセットされること" do
        patch activity_record_path(activity_record), params: bad_params
        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(flash[:alert]).to eq(failure_message)
        end
      end
    end

    context "他ユーザーのレコードを更新すると" do
      let(:other_bad_params) do
        {
          activity_record: {
            comment: "改ざん"
          }
        }
      end

      let(:other_activity_record) { create(:activity_record, user: other_user, light_time: other_light_time) }

      it "更新できず 404 を返すこと" do
        patch activity_record_path(other_activity_record), params: other_bad_params
        aggregate_failures do
          expect(response).to have_http_status(:not_found)
          expect(other_activity_record.reload.comment).not_to eq("改ざん")
        end
      end
    end
  end

  # =========================================================
  # PATCH /activity_records/:id/favorite
  # =========================================================
  describe "PATCH /activity_records/:id/favorite" do
    let!(:activity_record) do
      create(:activity_record, user: user, light_time: light_time, favorited: false)
    end

    context "favorited が false のとき" do
      it "true にトグルされること" do
        expect {
          patch favorite_activity_record_path(activity_record)
        }.to change { activity_record.reload.favorited }.from(false).to(true)
      end

      it "turbo_stream リクエストで 200 を返すこと" do
        patch favorite_activity_record_path(activity_record),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end
      end

      it "html リクエストで一覧ページへリダイレクトすること" do
        patch favorite_activity_record_path(activity_record)
        expect(response).to redirect_to(activity_records_path)
      end
    end

    context "favorited が true のとき" do
      before { activity_record.update!(favorited: true) }

      it "false にトグルされること" do
        expect {
          patch favorite_activity_record_path(activity_record)
        }.to change { activity_record.reload.favorited }.from(true).to(false)
      end
    end

    context "他ユーザーのレコードに対して操作すると" do
      let!(:other_activity_record) do
        create(:activity_record, user: other_user, light_time: other_light_time, favorited: false)
      end

      it "更新できず 404 を返すこと" do
        aggregate_failures do
          expect {
            patch favorite_activity_record_path(other_activity_record)
          }.not_to change { other_activity_record.reload.favorited }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end

  # =========================================================
  # DELETE /activity_records/:id (destroy)
  # =========================================================
  describe "DELETE /activity_records/:id" do
    let!(:activity_record) { create(:activity_record, user: user, light_time: light_time) }

    let(:success_message) do
      I18n.t("defaults.flash_message.deleted", item: ActivityRecord.model_name.human)
    end

    it "ActivityRecord が 1 件減ること" do
      expect { delete activity_record_path(activity_record) }
        .to change(ActivityRecord, :count).by(-1)
    end

    it "一覧ページへリダイレクトし、成功メッセージがセットされること" do
      delete activity_record_path(activity_record)
      aggregate_failures do
        expect(response).to redirect_to(activity_records_path)
        expect(flash[:notice]).to eq(success_message)
      end
    end

    context "他ユーザーのレコードに削除すると" do
      let!(:other_activity_record) { create(:activity_record, user: other_user, light_time: other_light_time) }

      it "削除できず 404 を返すこと" do
        aggregate_failures do
          expect {
            delete activity_record_path(other_activity_record)
          }.not_to change(ActivityRecord, :count)
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end

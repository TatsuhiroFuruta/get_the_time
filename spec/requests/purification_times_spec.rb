require "rails_helper"

RSpec.describe "PurificationTimes", type: :request do
  let(:user) { create(:user) }
  let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

  before { sign_in user }

  # =========================================================
  # GET /purification_time
  # =========================================================
  describe "GET /purification_time" do
    context "HTML リクエスト" do
      it "200 を返すこと" do
        get purification_time_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "JSON リクエスト" do
      it "running 状態を JSON で返すこと" do
        get purification_time_path, headers: { "Accept" => "application/json" }

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          json = JSON.parse(response.body)
          expect(json).to have_key("running")
          expect(json["running"]).to be false
        end
      end

      context "running 状態のとき" do
        let!(:purification_time) { create(:purification_time, :running, user: user) }

        it "running: true を返すこと" do
          get purification_time_path, headers: { "Accept" => "application/json" }
          json = JSON.parse(response.body)
          expect(json["running"]).to be true
        end
      end
    end

    context "未ログインのとき" do
      before { sign_out user }

      it "ログインページへリダイレクトされること" do
        get purification_time_path
        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  # =========================================================
  # PATCH /purification_time/start
  # =========================================================
  describe "PATCH /purification_time/start" do
    it "200 を返すこと" do
      patch start_purification_time_path
      expect(response).to have_http_status(:ok)
    end

    it "start! が実行されて running 状態になること" do
      patch start_purification_time_path
      expect(purification_time.reload).to be_running
    end
  end

  # =========================================================
  # PATCH /purification_time/stop
  # =========================================================
  describe "PATCH /purification_time/stop" do
    let!(:purification_time) do
      create(:purification_time,
             user: user,
             status: :running,
             remaining_time: 600,
             total_time: 600,
             started_at: 1.minute.ago)
    end

    it "200 を返すこと" do
      patch stop_purification_time_path
      expect(response).to have_http_status(:ok)
    end

    it "stop! が実行されて paused 状態に変わること" do
      patch stop_purification_time_path
      expect(purification_time.reload).to be_paused
    end
  end

  # =========================================================
  # PATCH /purification_time/reset
  # =========================================================
  describe "PATCH /purification_time/reset" do
    let!(:purification_time) { create(:purification_time, :paused, user: user) }

    it "200 を返すこと" do
      patch reset_purification_time_path
      expect(response).to have_http_status(:ok)
    end

    it "reset! が実行されて idle 状態に戻ること" do
      patch reset_purification_time_path
      expect(purification_time.reload).to be_idle
    end
  end
end

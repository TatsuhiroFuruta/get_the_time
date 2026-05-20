require "rails_helper"

RSpec.describe "LightTimes", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    sign_in user
  end

  describe "GET /light_times/new" do
    it "正常に表示される" do
      get new_light_time_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /light_times/:id" do
    let!(:light_time) { create(:light_time, user: user) }

    it "正常に表示される" do
      get light_time_path(light_time)
      expect(response).to have_http_status(:ok)
    end

    it "他人のデータにはアクセスできない" do
      other_light_time = create(:light_time, user: other_user)
      get light_time_path(other_light_time)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "GET /light_times/:id/edit" do
    let!(:light_time) { create(:light_time, user: user) }

    it "正常に表示される" do
      get edit_light_time_path(light_time)
      expect(response).to have_http_status(:ok)
    end

    it "他人のデータにはアクセスできない" do
      other_light_time = create(:light_time, user: other_user)
      get edit_light_time_path(other_light_time)
      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /light_times" do
    let(:success_message) do
      I18n.t("defaults.flash_message.created", item: LightTime.model_name.human)
    end

    let(:failure_message) do
      I18n.t("defaults.flash_message.not_created", item: LightTime.model_name.human)
    end

    context "正常系" do
      let(:valid_params) do
        {
          light_time: {
            action: "朝散歩",
            desired_self: "健康",
            characteristic: "継続"
          }
        }
      end

      it "作成できる" do
        expect {
          post light_times_path, params: valid_params
        }.to change(LightTime, :count).by(1)

        expect(response).to redirect_to(mypage_path)
        expect(flash[:notice]).to eq(success_message)
      end

      it "新しく作成したものが current になる" do
        create(:light_time, :current, user: user)

        post light_times_path, params: valid_params

        expect(LightTime.last.is_current).to be true

        expect(
          user.light_times.where(is_current: true).count
        ).to eq 1
      end
    end

    context "異常系" do
      let(:invalid_params) do
        {
          light_time: {
            action: "",
            desired_self: "健康"
          }
        }
      end

      it "作成できない" do
        expect {
          post light_times_path, params: invalid_params
        }.not_to change(LightTime, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq(failure_message)
      end
    end
  end

  describe "PATCH /light_times/:id" do
    let!(:light_time) { create(:light_time, user: user) }

    let(:success_message) do
      I18n.t("defaults.flash_message.updated", item: LightTime.model_name.human)
    end

    let(:failure_message) do
      I18n.t("defaults.flash_message.not_updated", item: LightTime.model_name.human)
    end

    context "正常系" do
      it "更新できる" do
        patch light_time_path(light_time), params: {
          light_time: { action: "夜散歩" }
        }

        expect(response).to redirect_to(light_time_path(light_time))
        expect(flash[:notice]).to eq(success_message)
        expect(light_time.reload.action).to eq ("夜散歩")
      end
    end

    context "異常系" do
      it "不正な値では更新できない" do
        patch light_time_path(light_time), params: {
          light_time: { action: "" }
        }

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq(failure_message)
        expect(light_time.reload.action).not_to eq("")
      end

      it "他人のデータは更新できない" do
        other_light_time = create(:light_time, user: other_user)

        patch light_time_path(other_light_time), params: {
          light_time: { action: "不正更新" }
        }

        expect(response).to have_http_status(:not_found)
        expect(other_light_time.reload.action).not_to eq("不正更新")
      end
    end
  end

  describe "DELETE /light_times/:id" do
    let!(:current_light_time) { create(:light_time, :current, user: user) }

    let!(:next_light_time) { create(:light_time, user: user) }

    let(:success_message) do
      I18n.t("defaults.flash_message.deleted", item: LightTime.model_name.human)
    end

    it "削除できる" do
      expect {
        delete light_time_path(current_light_time)
      }.to change(LightTime, :count).by(-1)

      expect(response).to have_http_status(:see_other)
      expect(response).to redirect_to(mypage_path)
      expect(flash[:notice]).to eq(success_message)
    end

    it "current 削除時は次が current になる" do
      delete light_time_path(current_light_time)
      expect(next_light_time.reload.is_current).to be true
    end

    it "他人のデータは削除できない" do
      other_light_time = create(:light_time, user: other_user)

      expect {
        delete light_time_path(other_light_time)
      }.not_to change(LightTime, :count)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /light_times/:id/switch" do
    let!(:light_time1) { create(:light_time, :current, user: user, action: "朝運動") }
    let!(:light_time2) { create(:light_time, user: user, action: "夜読書") }

    context "正常系" do
      it "current が切り替わる" do
        patch switch_light_time_path(light_time2), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:ok)
        expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        expect(light_time1.reload.is_current).to be false
        expect(light_time2.reload.is_current).to be true
      end
    end

    context "異常系" do
      it "他人のデータにはアクセスできない" do
        other_light_time = create(:light_time, user: other_user)
        patch switch_light_time_path(other_light_time), headers: { "ACCEPT" => "text/vnd.turbo-stream.html" }
        expect(response).to have_http_status(:not_found)
      end
    end
  end
end

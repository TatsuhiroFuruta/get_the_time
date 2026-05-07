require 'rails_helper'

RSpec.describe "DarkTimes", type: :request do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "POST /dark_time" do
    let(:success_message) do
      I18n.t('defaults.flash_message.created', item: DarkTime.model_name.human)
    end

    let(:failure_message) do
      I18n.t('defaults.flash_message.not_created', item: DarkTime.model_name.human)
    end

    context "正常系" do
      it "DarkTimeを作成できる" do
        expect {
          post dark_time_path, params: {
            dark_time: {
              behavior: "スマホを触りすぎる",
              characteristic: "集中力がない",
              unwanted_future: "生産性が下がる"
            }
          }
        }.to change(DarkTime, :count).by(1)

        expect(response).to redirect_to(mypage_path)
        expect(flash[:notice]).to eq(success_message)
      end
    end

    context "異常系" do
      it "behaviorがないと作成できない" do
        expect {
          post dark_time_path, params: {
            dark_time: {
              behavior: ""
            }
          }
        }.not_to change(DarkTime, :count)

        expect(response).to have_http_status(:unprocessable_content)
        expect(flash[:alert]).to eq(failure_message)
      end
    end

    context "既に作成済みの場合" do
      let!(:existing_dark_time) { create(:dark_time, user: user) }

      it "2件目は作成できず、編集画面にリダイレクトされる" do
        expect {
          post dark_time_path, params: {
            dark_time: { behavior: "別の行動" }
          }
        }.not_to change(DarkTime, :count)

        expect(response).to redirect_to(edit_dark_time_path)
        expect(flash[:alert]).to eq(
          I18n.t('defaults.flash_message.already_exists', item: DarkTime.model_name.human)
        )
      end
    end
  end

  describe "PATCH /dark_time" do
    let!(:dark_time) { create(:dark_time, user: user) }

    let(:success_message) do
      I18n.t('defaults.flash_message.updated', item: DarkTime.model_name.human)
    end

    let(:failure_message) do
      I18n.t('defaults.flash_message.not_updated', item: DarkTime.model_name.human)
    end

    it "更新できる" do
      patch dark_time_path, params: {
        dark_time: { behavior: "改善後" }
      }

      expect(response).to redirect_to(dark_time_path)
      expect(flash[:notice]).to eq(success_message)
      expect(dark_time.reload.behavior).to eq("改善後")
    end

    it "バリデーションエラー時は更新されない" do
      patch dark_time_path, params: {
        dark_time: { behavior: "" }
      }

      expect(response).to have_http_status(:unprocessable_content)
      expect(flash[:alert]).to eq(failure_message)
      expect(dark_time.reload.behavior).not_to eq("")
    end
  end

  describe "GET /dark_time" do
    let!(:dark_time) { create(:dark_time, user: user) }

    it "詳細画面が表示される" do
      get dark_time_path

      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /dark_time/new" do
    context "DarkTimeが未作成の場合" do
      it "新規作成画面が表示される" do
        get new_dark_time_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "既にDarkTimeが作成済みの場合" do
      let!(:dark_time) { create(:dark_time, user: user) }

      it "編集画面にリダイレクトされる" do
        get new_dark_time_path
        expect(response).to redirect_to(edit_dark_time_path)
        expect(flash[:alert]).to eq(
          I18n.t('defaults.flash_message.already_exists', item: DarkTime.model_name.human)
        )
      end
    end
  end

  describe "GET /dark_time/edit" do
    context "DarkTimeが存在する場合" do
      let!(:dark_time) { create(:dark_time, user: user) }

      it "編集画面が表示される" do
        get edit_dark_time_path
        expect(response).to have_http_status(:ok)
      end
    end

    context "DarkTimeが存在しない場合" do
      it "新規作成画面にリダイレクトされる" do
        get edit_dark_time_path
        expect(response).to redirect_to(new_dark_time_path)
        expect(flash[:alert]).to eq(
          I18n.t('defaults.flash_message.not_found', item: DarkTime.model_name.human)
        )
      end
    end
  end
end

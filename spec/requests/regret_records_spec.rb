require "rails_helper"

RSpec.describe "RegretRecords", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    sign_in user
  end

  describe "GET /regret_records" do
    it "正常に表示される" do
      get regret_records_path
      expect(response).to have_http_status(:ok)
    end

    it "自分の記録のみ表示される" do
      own = create(:regret_record, user: user, content: "自分の後悔")
      create(:regret_record, user: other_user, content: "他人の後悔")

      get regret_records_path

      aggregate_failures do
        expect(response.body).to include("自分の後悔")
        expect(response.body).not_to include("他人の後悔")
      end
    end
  end

  describe "GET /regret_records/new" do
    it "正常に表示される" do
      get new_regret_record_path
      expect(response).to have_http_status(:ok)
    end
  end

  describe "GET /regret_records/:id" do
    it "自分の記録の詳細が表示される" do
      regret_record = create(:regret_record, user: user, content: "自分の後悔")

      get regret_record_path(regret_record)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("自分の後悔")
      end
    end

    it "他人の記録にアクセスすると 404 を返す" do
      other_regret_record = create(:regret_record, user: other_user)

      get regret_record_path(other_regret_record)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "POST /regret_records" do
    let(:success_message) do
      I18n.t("defaults.flash_message.created", item: RegretRecord.model_name.human)
    end

    let(:failure_message) do
      I18n.t("defaults.flash_message.not_created", item: RegretRecord.model_name.human)
    end

    context "正常系" do
      let(:valid_params) do
        {
          regret_record: {
            title: "後悔した日",
            content: "やるべきことができなかった"
          }
        }
      end

      it "作成できる" do
        expect {
          post regret_records_path, params: valid_params
        }.to change(user.regret_records, :count).by(1)

        aggregate_failures do
          expect(response).to redirect_to(regret_records_path)
          expect(flash[:notice]).to eq(success_message)
        end
      end
    end

    context "異常系" do
      let(:invalid_params) do
        {
          regret_record: {
            title: "タイトルのみ",
            content: ""
          }
        }
      end

      it "作成できない" do
        expect {
          post regret_records_path, params: invalid_params
        }.not_to change(RegretRecord, :count)

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(flash[:alert]).to eq(failure_message)
        end
      end
    end
  end
end

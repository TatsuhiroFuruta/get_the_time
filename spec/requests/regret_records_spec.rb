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

  describe "GET /regret_records/:id/edit" do
    it "自分の記録の編集画面が表示される" do
      regret_record = create(:regret_record, user: user, content: "編集前の内容")

      get edit_regret_record_path(regret_record)

      aggregate_failures do
        expect(response).to have_http_status(:ok)
        expect(response.body).to include("編集前の内容")
      end
    end

    it "他人の記録の編集画面にアクセスすると 404 を返す" do
      other_regret_record = create(:regret_record, user: other_user)

      get edit_regret_record_path(other_regret_record)

      expect(response).to have_http_status(:not_found)
    end
  end

  describe "PATCH /regret_records/:id" do
    let(:success_message) do
      I18n.t("defaults.flash_message.updated", item: RegretRecord.model_name.human)
    end

    context "正常系" do
      it "更新でき、詳細画面にリダイレクトされる" do
        regret_record = create(:regret_record, user: user, content: "編集前の内容")

        patch regret_record_path(regret_record), params: { regret_record: { content: "編集後の内容" } }

        aggregate_failures do
          expect(response).to redirect_to(regret_record_path(regret_record))
          expect(flash[:notice]).to eq(success_message)
          expect(regret_record.reload.content).to eq("編集後の内容")
        end
      end
    end

    context "異常系" do
      it "内容が空では更新できない" do
        regret_record = create(:regret_record, user: user, content: "編集前の内容")

        patch regret_record_path(regret_record), params: { regret_record: { content: "" } }

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(regret_record.reload.content).to eq("編集前の内容")
        end
      end
    end

    it "他人の記録を更新しようとすると 404 を返す" do
      other_regret_record = create(:regret_record, user: other_user, content: "他人の内容")

      patch regret_record_path(other_regret_record), params: { regret_record: { content: "改ざん" } }

      aggregate_failures do
        expect(response).to have_http_status(:not_found)
        expect(other_regret_record.reload.content).to eq("他人の内容")
      end
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

  describe "DELETE /regret_records/:id" do
    let(:success_message) do
      I18n.t("defaults.flash_message.deleted", item: RegretRecord.model_name.human)
    end

    it "自分の記録を削除でき、一覧にリダイレクトされる" do
      regret_record = create(:regret_record, user: user)

      expect {
        delete regret_record_path(regret_record)
      }.to change(user.regret_records, :count).by(-1)

      aggregate_failures do
        expect(response).to redirect_to(regret_records_path)
        expect(flash[:notice]).to eq(success_message)
      end
    end

    it "他人の記録を削除しようとすると 404 を返し、削除されない" do
      other_regret_record = create(:regret_record, user: other_user)

      aggregate_failures do
        expect {
          delete regret_record_path(other_regret_record)
        }.not_to change(RegretRecord, :count)
        expect(response).to have_http_status(:not_found)
      end
    end
  end

  describe "PATCH /regret_records/:id/favorite" do
    let!(:regret_record) { create(:regret_record, user: user, favorited: false) }

    context "favorited が false のとき" do
      it "true にトグルされること" do
        expect {
          patch favorite_regret_record_path(regret_record)
        }.to change { regret_record.reload.favorited }.from(false).to(true)
      end

      it "turbo_stream リクエストで 200 を返すこと" do
        patch favorite_regret_record_path(regret_record),
              headers: { "Accept" => "text/vnd.turbo-stream.html" }
        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.media_type).to eq("text/vnd.turbo-stream.html")
        end
      end

      it "html リクエストで一覧ページへリダイレクトすること" do
        patch favorite_regret_record_path(regret_record)
        expect(response).to redirect_to(regret_records_path)
      end
    end

    context "favorited が true のとき" do
      before { regret_record.update!(favorited: true) }

      it "false にトグルされること" do
        expect {
          patch favorite_regret_record_path(regret_record)
        }.to change { regret_record.reload.favorited }.from(true).to(false)
      end
    end

    context "他ユーザーのレコードに対して操作すると" do
      let!(:other_regret_record) { create(:regret_record, user: other_user, favorited: false) }

      it "更新できず 404 を返すこと" do
        aggregate_failures do
          expect {
            patch favorite_regret_record_path(other_regret_record)
          }.not_to change { other_regret_record.reload.favorited }
          expect(response).to have_http_status(:not_found)
        end
      end
    end
  end
end

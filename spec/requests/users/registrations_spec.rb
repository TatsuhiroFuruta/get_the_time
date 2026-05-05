require 'rails_helper'

RSpec.describe "User Registrations", type: :request do
  describe "POST /users" do
    context "正常系" do
      it "ユーザーが登録できる" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "山田太郎",
              email: "new@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.to change(User, :count).by(1)

        expect(response).to redirect_to(root_path)
      end

      it "nameが30文字なら登録できる" do
        valid_name = "a" * 30

        expect {
          post user_registration_path, params: {
            user: {
              name: valid_name,
              email: "new@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.to change(User, :count).by(1)
      end
    end

    context "異常系" do
      it "登録失敗する（emailなし）" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "山田太郎",
              email: "",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)

        expect(response.body).to include("メールアドレスを入力してください")
      end

      it "nameがないと登録できない" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "",
              email: "new@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)

        expect(response.body).to include("名前を入力してください")
      end

      it "nameが31文字以上だと登録できない" do
        long_name = "a" * 31

        expect {
          post user_registration_path, params: {
            user: {
              name: long_name,
              email: "new@example.com",
              password: "password123",
              password_confirmation: "password123"
            }
          }
        }.not_to change(User, :count)

        expect(response.body).to include("名前は30文字以内で入力してください")
      end

      it "パスワードに空白が含まれていると登録できない" do
        expect {
          post user_registration_path, params: {
            user: {
              name: "山田太郎",
              email: "new@example.com",
              password: "pass word123",
              password_confirmation: "pass word123"
            }
          }
        }.not_to change(User, :count)

        expect(response.body).to include("パスワードにスペースを含めることはできません")
      end
    end
  end
end

require "rails_helper"

RSpec.describe "User Registrations", type: :request do
  describe "POST /users" do
    context "正常系" do
      it "ユーザーが登録できる" do
        aggregate_failures do
          expect {
            post user_registration_path, params: {
              user: {
                name: "山田太郎",
                email: "new@example.com",
                password: "password123",
                password_confirmation: "password123",
                agreement: "1"
              }
            }
          }.to change(User, :count).by(1)

          expect(response).to redirect_to(root_path)
        end
      end

      it "nameが30文字なら登録できる" do
        valid_name = "a" * 30

        expect {
          post user_registration_path, params: {
            user: {
              name: valid_name,
              email: "new@example.com",
              password: "password123",
              password_confirmation: "password123",
              agreement: "1"
            }
          }
        }.to change(User, :count).by(1)
      end
    end

    context "異常系" do
      it "登録失敗する（emailなし）" do
        aggregate_failures do
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
      end

      it "登録失敗する（emailが既に登録済み）" do
        create(:user, email: "taken@example.com")

        aggregate_failures do
          expect {
            post user_registration_path, params: {
              user: {
                name: "山田太郎",
                email: "taken@example.com",
                password: "password123",
                password_confirmation: "password123",
                agreement: "1"
              }
            }
          }.not_to change(User, :count)

          expect(response.body).to include("メールアドレスが登録できません。別のメールアドレスで登録してください")
        end
      end

      it "nameがないと登録できない" do
        aggregate_failures do
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
      end

      it "nameが31文字以上だと登録できない" do
        long_name = "a" * 31

        aggregate_failures do
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
      end

      it "パスワードに空白が含まれていると登録できない" do
        aggregate_failures do
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

      it "利用規約・プライバシーポリシーに同意しない（agreement=\"0\"）と登録できない" do
        aggregate_failures do
          expect {
            post user_registration_path, params: {
              user: {
                name: "山田太郎",
                email: "new@example.com",
                password: "password123",
                password_confirmation: "password123",
                agreement: "0"
              }
            }
          }.not_to change(User, :count)

          expect(response.body).to include("利用規約・プライバシーポリシーに同意してください")
        end
      end
    end
  end

  describe "GET /users/account" do
    context "ログイン済みの場合" do
      let(:user) { create(:user, name: "元の名前", email: "original@example.com") }

      before { sign_in user }

      it "アカウント情報画面が表示される" do
        get user_account_path

        aggregate_failures do
          expect(response).to have_http_status(:ok)
          expect(response.body).to include("元の名前")
          expect(response.body).to include("original@example.com")
        end
      end
    end

    context "未ログインの場合" do
      it "ログイン画面にリダイレクトされる" do
        get user_account_path

        expect(response).to redirect_to(new_user_session_path)
      end
    end
  end

  describe "PATCH /users" do
    let(:user) { create(:user, name: "元の名前", email: "original@example.com", password: "password123", password_confirmation: "password123") }

    before { sign_in user }

    context "正常系" do
      it "現在のパスワードを入力すると名前を更新でき、アカウント情報画面にリダイレクトされる" do
        patch user_registration_path, params: {
          user: {
            name: "新しい名前",
            current_password: "password123"
          }
        }

        aggregate_failures do
          expect(response).to redirect_to(user_account_path)
          expect(flash[:notice]).to eq(I18n.t("devise.registrations.updated"))
          expect(user.reload.name).to eq("新しい名前")
        end
      end

      it "現在のパスワードを入力するとメールアドレスを更新できる" do
        patch user_registration_path, params: {
          user: {
            email: "updated@example.com",
            current_password: "password123"
          }
        }

        aggregate_failures do
          expect(response).to redirect_to(user_account_path)
          expect(user.reload.email).to eq("updated@example.com")
        end
      end

      it "現在のパスワードを入力すると新しいパスワードに変更でき、新パスワードでログインできる" do
        patch user_registration_path, params: {
          user: {
            password: "newpassword123",
            password_confirmation: "newpassword123",
            current_password: "password123"
          }
        }

        aggregate_failures do
          expect(response).to redirect_to(user_account_path)
          expect(user.reload.valid_password?("newpassword123")).to be true
        end
      end
    end

    context "異常系" do
      it "現在のパスワードがないと更新できない" do
        patch user_registration_path, params: {
          user: {
            name: "新しい名前"
          }
        }

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("現在のパスワードを入力してください")
          expect(user.reload.name).to eq("元の名前")
        end
      end

      it "現在のパスワードが誤っていると更新できない" do
        patch user_registration_path, params: {
          user: {
            name: "新しい名前",
            current_password: "wrongpassword"
          }
        }

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("現在のパスワードは不正な値です")
          expect(user.reload.name).to eq("元の名前")
        end
      end

      it "nameを空にすると更新できない" do
        patch user_registration_path, params: {
          user: {
            name: "",
            current_password: "password123"
          }
        }

        aggregate_failures do
          expect(response).to have_http_status(:unprocessable_content)
          expect(response.body).to include("名前を入力してください")
          expect(user.reload.name).to eq("元の名前")
        end
      end
    end
  end
end

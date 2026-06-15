require "rails_helper"

RSpec.describe "PasswordResets", type: :request do
  let!(:user) { create(:user) }

  before { ActionMailer::Base.deliveries.clear }

  it "再設定メールを送信し、新しいパスワードに変更できる" do
    # 申請するとメールが1通送信される
    expect {
      post user_password_path, params: { user: { email: user.email } }
    }.to change { ActionMailer::Base.deliveries.size }.by(1)
    expect(response).to redirect_to(new_user_session_path)

    # 送信メールから再設定トークンを取り出す（quoted-printable を decoded で復元）
    mail = ActionMailer::Base.deliveries.last
    body = mail.html_part&.body&.decoded || mail.body.decoded
    token = body[/reset_password_token=([^"&\s]+)/, 1]
    expect(token).to be_present

    # トークンを使って新パスワードを設定
    put user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    # 完了後はルートへリダイレクトし、パスワードが新しいものに更新されている
    aggregate_failures do
      expect(response).to redirect_to(root_path)
      expect(user.reload.valid_password?("newpassword123")).to be(true)
    end
  end

  it "一度使用したトークンは再利用できない" do
    # 変更後の自動ログインを無効化し、2 回目を「未ログインの第三者による再利用」として検証する
    allow(Devise).to receive(:sign_in_after_reset_password).and_return(false)

    token = user.send_reset_password_instructions

    # 1 回目は正常に変更できる
    put user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }
    expect(user.reload.valid_password?("newpassword123")).to be(true)

    # 2 回目に同じトークンを使っても変更できない（トークンは使用時に失効する）
    put user_password_path, params: {
      user: {
        reset_password_token: token,
        password: "anotherpass456",
        password_confirmation: "anotherpass456"
      }
    }

    aggregate_failures do
      expect(user.reload.valid_password?("anotherpass456")).to be(false)
      expect(user.valid_password?("newpassword123")).to be(true)
      # 完了せず、再設定フォームが再表示される
      expect(response).not_to redirect_to(root_path)
      expect(response.body).to include("新しいパスワードの設定")
    end
  end

  it "無効なトークンではパスワードを変更できない" do
    put user_password_path, params: {
      user: {
        reset_password_token: "invalid-token",
        password: "newpassword123",
        password_confirmation: "newpassword123"
      }
    }

    aggregate_failures do
      # パスワードは元（password123）のまま変わらない
      expect(user.reload.valid_password?("password123")).to be(true)
      expect(user.valid_password?("newpassword123")).to be(false)
      # 完了せず、再設定フォームが再表示される
      expect(response).not_to redirect_to(root_path)
      expect(response.body).to include("新しいパスワードの設定")
    end
  end

  it "期限切れのトークンではパスワードを変更できない" do
    token = user.send_reset_password_instructions

    # 有効期限（reset_password_within）を過ぎた時点で変更を試みる
    travel_to (Devise.reset_password_within + 1.hour).from_now do
      put user_password_path, params: {
        user: {
          reset_password_token: token,
          password: "newpassword123",
          password_confirmation: "newpassword123"
        }
      }

      aggregate_failures do
        # パスワードは元（password123）のまま変わらない
        expect(user.reload.valid_password?("password123")).to be(true)
        expect(user.valid_password?("newpassword123")).to be(false)
        # 完了せず、再設定フォームが再表示される
        expect(response).not_to redirect_to(root_path)
        expect(response.body).to include("新しいパスワードの設定")
      end
    end
  end

  it "未登録のメールアドレスではメールを送信しないが、応答は登録済みと変わらない" do
    # paranoid モードにより、登録の有無を判別されない（ユーザー列挙対策）
    expect {
      post user_password_path, params: { user: { email: "unknown@example.com" } }
    }.not_to(change { ActionMailer::Base.deliveries.size })

    # 登録済みアドレスのときと同じくログイン画面へリダイレクトし、同一文言を表示する
    aggregate_failures do
      expect(response).to redirect_to(new_user_session_path)
      expect(flash[:notice]).to eq(I18n.t("devise.passwords.send_paranoid_instructions"))
    end
  end
end

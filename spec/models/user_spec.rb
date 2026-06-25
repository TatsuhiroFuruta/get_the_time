require "rails_helper"

RSpec.describe User, type: :model do
  # =========================================================
  # アソシエーション
  # =========================================================
  describe "アソシエーション" do
    it "dark_time を dependent: :destroy で1つ持つこと" do
      association = described_class.reflect_on_association(:dark_time)
      aggregate_failures do
        expect(association.macro).to eq :has_one
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "light_times を dependent: :destroy で複数持つこと" do
      association = described_class.reflect_on_association(:light_times)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "activity_records を dependent: :destroy で複数持つこと" do
      association = described_class.reflect_on_association(:activity_records)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "purification_time を dependent: :destroy で1つ持つこと" do
      association = described_class.reflect_on_association(:purification_time)
      aggregate_failures do
        expect(association.macro).to eq :has_one
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "pomodoro_setting を dependent: :destroy で1つ持つこと" do
      association = described_class.reflect_on_association(:pomodoro_setting)
      aggregate_failures do
        expect(association.macro).to eq :has_one
        expect(association.options[:dependent]).to eq :destroy
      end
    end

    it "regret_records を dependent: :destroy で複数持つこと" do
      association = described_class.reflect_on_association(:regret_records)
      aggregate_failures do
        expect(association.macro).to eq :has_many
        expect(association.options[:dependent]).to eq :destroy
      end
    end
  end

  # =========================================================
  # コールバック
  # =========================================================
  describe "after_create :create_pomodoro_setting" do
    it "User 作成時にデフォルト値の PomodoroSetting が生成されること" do
      user = create(:user)
      aggregate_failures do
        expect(user.pomodoro_setting).to be_present
        expect(user.pomodoro_setting.work_duration).to eq 25
        expect(user.pomodoro_setting.break_duration).to eq 5
      end
    end
  end

  describe "nameのバリデーション" do
    it "nameがあれば有効" do
      user = build(:user, name: "テスト")
      expect(user).to be_valid
    end

    it "nameがないと無効" do
      user = build(:user, name: nil)
      aggregate_failures do
        expect(user).to be_invalid
        expect(user.errors[:name]).to be_present
      end
    end

    it "nameが30文字以内なら有効" do
      user = build(:user, name: "a" * 30)
      expect(user).to be_valid
    end

    it "nameが31文字以上だと無効" do
      user = build(:user, name: "a" * 31)
      aggregate_failures do
        expect(user).to be_invalid
        expect(user.errors[:name]).to be_present
      end
    end
  end

  describe "passwordのバリデーション" do
    it "スペースを含むと無効" do
      user = build(:user,
        password: "pass word",
        password_confirmation: "pass word"
      )

      aggregate_failures do
        expect(user).to be_invalid
        # カスタムメッセージを書いているから、includeを記述
        expect(user.errors[:password]).to include("にスペースを含めることはできません")
      end
    end

    it "スペースがなければ有効" do
      user = build(:user,
        password: "password123",
        password_confirmation: "password123"
      )

      expect(user).to be_valid
    end

    it "6文字未満だと無効" do
      user = build(:user,
        password: "pass1",
        password_confirmation: "pass1"
      )

      aggregate_failures do
        expect(user).to be_invalid
        expect(user.errors[:password]).to be_present
      end
    end

    it "6文字以上なら有効" do
      user = build(:user,
        password: "pass12",
        password_confirmation: "pass12"
      )

      expect(user).to be_valid
    end
  end

  # =========================================================
  # agreement（利用規約・プライバシーポリシーへの同意）のバリデーション
  # =========================================================
  describe "agreementのバリデーション" do
    it "チェックあり（\"1\"）なら新規登録時に有効" do
      user = build(:user, agreement: "1")
      expect(user).to be_valid(:create)
    end

    it "チェックなし（\"0\"）だと新規登録時に無効でメッセージが出る" do
      user = build(:user, agreement: "0")

      aggregate_failures do
        expect(user).to be_invalid(:create)
        expect(user.errors[:agreement]).to include("に同意してください")
      end
    end

    it "agreement 未設定（nil）でも有効（OmniAuth 経由の作成を壊さないよう acceptance は nil をスキップする）" do
      user = build(:user, agreement: nil)
      expect(user).to be_valid(:create)
    end

    it "既存ユーザーの更新（:update）では同意を問わない" do
      user = create(:user, agreement: "1")
      user.agreement = "0"
      expect(user).to be_valid(:update)
    end
  end

  # =========================================================
  # .from_omniauth（Google 認証）
  # =========================================================
  describe ".from_omniauth" do
    def build_auth(email:, name: "グーグル太郎", uid: "uid-123")
      OmniAuth::AuthHash.new(
        provider: "google_oauth2",
        uid: uid,
        info: { email: email, name: name }
      )
    end

    context "未登録のメールアドレスの場合" do
      it "provider/uid/名前を設定した新規ユーザーを作成する" do
        auth = build_auth(email: "new@example.com", name: "新規太郎")

        expect {
          @user = described_class.from_omniauth(auth)
        }.to change(described_class, :count).by(1)

        aggregate_failures do
          expect(@user).to be_persisted
          expect(@user.email).to eq("new@example.com")
          expect(@user.provider).to eq("google_oauth2")
          expect(@user.uid).to eq("uid-123")
          expect(@user.name).to eq("新規太郎")
          # ランダムパスワードが設定され、有効なレコードになっている
          expect(@user.encrypted_password).to be_present
        end
      end
    end

    context "同じメールアドレスの既存ユーザーがいる場合" do
      let!(:existing_user) { create(:user, email: "existing@example.com", name: "既存花子") }

      it "新規作成せず既存ユーザーに provider/uid を紐付ける" do
        auth = build_auth(email: "existing@example.com", name: "別の名前")

        expect {
          described_class.from_omniauth(auth)
        }.not_to change(described_class, :count)

        existing_user.reload
        aggregate_failures do
          expect(existing_user.provider).to eq("google_oauth2")
          expect(existing_user.uid).to eq("uid-123")
          # 既存ユーザーの名前は上書きしない
          expect(existing_user.name).to eq("既存花子")
        end
      end

      it "既存ユーザーのパスワードを上書きしない" do
        original_encrypted = existing_user.encrypted_password
        auth = build_auth(email: "existing@example.com")

        described_class.from_omniauth(auth)

        expect(existing_user.reload.encrypted_password).to eq(original_encrypted)
      end
    end

    context "provider/uid で連携済みのユーザーがメールアドレスを変更した場合" do
      # 過去に Google 連携済み（uid 保存済み）のユーザー
      let!(:linked_user) do
        create(:user, email: "old@example.com", name: "連携済み太郎",
               provider: "google_oauth2", uid: "uid-123")
      end

      it "メールが変わっても uid で同一ユーザーを引き当て、新規作成しない" do
        # Google 側で別のメールアドレスになって戻ってきた（uid は不変）
        auth = build_auth(email: "new@example.com", uid: "uid-123")

        aggregate_failures do
          expect {
            described_class.from_omniauth(auth)
          }.not_to change(described_class, :count)

          expect(described_class.find_by(uid: "uid-123").id).to eq(linked_user.id)
        end
      end
    end
  end
end

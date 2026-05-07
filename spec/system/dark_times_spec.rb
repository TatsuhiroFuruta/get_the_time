require 'rails_helper'

RSpec.describe "DarkTimes", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "DarkTime作成" do
    context "正常系" do
      it "作成後にマイページで表示される" do
        # 新規作成ページにアクセス
        visit new_dark_time_path

        # フォームに入力
        fill_in "闇の時間での行動", with: "スマホを触りすぎる"
        fill_in "避けたい未来", with: "生産性が下がる"
        fill_in "闇の時間の特徴", with: "集中力がない"

        # 作成ボタンをクリック
        click_button "登録する"

        # マイページにリダイレクトされる
        expect(page).to have_current_path(mypage_path)

        # 作成したDarkTimeが表示される
        expect(page).to have_content("スマホを触りすぎる")
        expect(page).to have_content("生産性が下がる")

        # フラッシュメッセージが表示される
        expect(page).to have_content(
          I18n.t('defaults.flash_message.created', item: DarkTime.model_name.human)
        )
      end
    end

    context "異常系" do
      it "behaviorが未入力の場合、作成できない" do
        visit new_dark_time_path

        # behaviorを未入力のまま送信
        fill_in "避けたい未来", with: "生産性が下がる"
        click_button "登録する"

        # エラーメッセージが表示される
        expect(page).to have_content("闇の時間での行動を入力してください")

        expect(page).to have_content(
          I18n.t('defaults.flash_message.not_created', item: DarkTime.model_name.human)
        )

        # 作成画面に留まる
        expect(page).to have_current_path(new_dark_time_path)
      end
    end
  end

  describe "DarkTime編集" do
    let!(:dark_time) { create(:dark_time, user: user, behavior: "元の行動") }

    context "正常系" do
      it "編集後にマイページで表示される" do
        visit edit_dark_time_path

        fill_in "闇の時間での行動", with: "改善後の行動"
        click_button "更新する"

        expect(page).to have_current_path(dark_time_path)
        expect(page).to have_content("改善後の行動")
        expect(page).to have_content(
          I18n.t('defaults.flash_message.updated', item: DarkTime.model_name.human)
        )
      end
    end

    context "異常系" do
      it "behaviorを空にすると更新できない" do
        visit edit_dark_time_path

        fill_in "闇の時間での行動", with: ""
        click_button "更新する"

        expect(page).to have_content("闇の時間での行動を入力してください")
        expect(page).to have_content(
          I18n.t('defaults.flash_message.not_updated', item: DarkTime.model_name.human)
        )
        expect(page).to have_current_path(edit_dark_time_path)
      end
    end
  end

  describe "DarkTime詳細表示" do
    let!(:dark_time) { create(:dark_time, user: user, behavior: "スマホを触りすぎる") }

    it "詳細ページで内容が表示される" do
      visit dark_time_path

      expect(page).to have_content("スマホを触りすぎる")
      expect(page).to have_content(dark_time.unwanted_future)
      expect(page).to have_content(dark_time.characteristic)
    end
  end

  describe "DarkTimeが未作成の場合" do
    it "newページにアクセスすると新規作成画面が表示される" do
      visit new_dark_time_path

      expect(page).to have_content("闇の時間での活動内容登録")
      expect(page).to have_field("闇の時間での行動")
      expect(page).to have_button("登録する")
    end
  end

  describe "DarkTimeが作成済みの場合" do
    let!(:dark_time) { create(:dark_time, user: user) }

    it "newページにアクセスすると編集画面にリダイレクトされる" do
      visit new_dark_time_path

      expect(page).to have_current_path(edit_dark_time_path)
      expect(page).to have_content(
        I18n.t('defaults.flash_message.already_exists', item: DarkTime.model_name.human)
      )
    end
  end
end

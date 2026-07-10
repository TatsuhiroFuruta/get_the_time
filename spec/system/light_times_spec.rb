require "rails_helper"

RSpec.describe "LightTimes", type: :system do
  let(:user) { create(:user) }

  before do
    sign_in user
  end

  describe "LightTime のCRUD" do
    describe "新規作成" do
      it "新規作成できること" do
        visit new_light_time_path

        fill_in "光の時間での行動", with: "朝のヨガ"
        fill_in "なりたい自分", with: "穏やかな自分"
        fill_in "光の時間の特徴", with: "リラックス効果"

        click_button "登録する"

        aggregate_failures do
          expect(page).to have_current_path(mypage_path)

          expect(page).to have_content(
            I18n.t("defaults.flash_message.created", item: LightTime.model_name.human)
          )

          expect(page).to have_content("朝のヨガ")
          expect(page).to have_content("穏やかな自分")
        end
      end

      it "必須項目未入力では作成できないこと" do
        visit new_light_time_path

        fill_in "光の時間での行動", with: ""

        click_button "登録する"

        aggregate_failures do
          expect(page).to have_content("光の時間での行動を入力してください")
          expect(page).to have_content(
            I18n.t("defaults.flash_message.not_created", item: LightTime.model_name.human)
          )

          expect(page).to have_current_path(new_light_time_path)
        end
      end

      it "キャンセルでマイページへ戻ること" do
        visit new_light_time_path

        click_link "キャンセル"

        expect(page).to have_current_path(mypage_path)
      end
    end

    describe "詳細表示" do
      let!(:light_time) { create(:light_time, user: user, action: "朝のヨガ", desired_self: "穏やかな自分", characteristic: "リラックス効果") }

      it "詳細が表示されること" do
        visit light_time_path(light_time)

        aggregate_failures do
          expect(page).to have_content("朝のヨガ")
          expect(page).to have_content("穏やかな自分")
          expect(page).to have_content("リラックス効果")
        end
      end

      it "マイページへ戻れること" do
        visit light_time_path(light_time)

        click_link "← マイページに戻る"

        expect(page).to have_current_path(mypage_path)
      end

      it "なりたい自分・特徴の改行が保持されて表示されること" do
        light_time.update!(desired_self: "自分1\n自分2", characteristic: "特徴1\n特徴2")

        visit light_time_path(light_time)

        aggregate_failures do
          expect(page).to have_css("div.whitespace-pre-wrap", text: "自分1")
          expect(page).to have_css("div.whitespace-pre-wrap", text: "特徴1")
        end
      end
    end

    describe "編集" do
      let!(:light_time) { create(:light_time, user: user, action: "朝のヨガ") }

      it "編集できること" do
        visit edit_light_time_path(light_time)

        fill_in "光の時間での行動", with: "夜の読書"
        click_button "更新する"

        aggregate_failures do
          expect(page).to have_current_path(
            light_time_path(light_time)
          )
          expect(page).to have_content(
            I18n.t("defaults.flash_message.updated", item: LightTime.model_name.human)
          )

          expect(page).to have_content("夜の読書")
        end
      end

      it "必須項目未入力では更新できないこと" do
        visit edit_light_time_path(light_time)

        fill_in "光の時間での行動", with: ""

        click_button "更新する"

        aggregate_failures do
          expect(page).to have_content("光の時間での行動を入力してください")
          expect(page).to have_content(
            I18n.t("defaults.flash_message.not_updated", item: LightTime.model_name.human)
          )
          expect(page).to have_current_path(
            edit_light_time_path(light_time)
          )
        end
      end

      it "キャンセルで詳細画面へ戻ること" do
        visit edit_light_time_path(light_time)

        click_link "キャンセル"

        expect(page).to have_current_path(
          light_time_path(light_time)
        )
      end
    end

    describe "削除" do
      let!(:light_time) { create(:light_time, :current, user: user) }

      it "削除できること" do
        visit light_time_path(light_time)

        accept_confirm do
          click_link "削除"
        end

        aggregate_failures do
          expect(page).to have_current_path(mypage_path)

          expect(page).to have_content(
            I18n.t("defaults.flash_message.deleted", item: LightTime.model_name.human)
          )
        end
      end

      context "current を削除した場合" do
        let!(:current_light_time) { create(:light_time, :current, user: user, action: "朝のヨガ", created_at: 2.days.ago) }
        let!(:next_light_time) { create(:light_time, user: user, action: "夜の読書", created_at: 1.day.ago) }

        it "current を削除すると次が表示されること" do
          visit light_time_path(current_light_time)

          accept_confirm do
            click_link "削除"
          end

          aggregate_failures do
            expect(page).to have_current_path(mypage_path)
            expect(page).to have_content("夜の読書")
          end
        end
      end
    end
  end

  describe "LightTime 切り替え機能", js: true do
    let!(:light_time1) { create(:light_time, :current, user: user, action: "朝のヨガ", created_at: 2.days.ago) }
    let!(:light_time2) { create(:light_time, user: user, action: "夜の読書", created_at: 1.day.ago) }

    context "ボタン操作" do
      it "次の LightTime に切り替えられること" do
        visit mypage_path

        expect(page).to have_content("朝のヨガ")

        find("button", text: ">").click

        aggregate_failures do
          expect(page).to have_content("夜の読書")

          expect(light_time2.reload.is_current).to be true
        end
      end
    end

    context "切り替え先が別タブで削除済みの場合" do
      it "マイページへ戻され、見つからない旨のメッセージが表示されること" do
        visit mypage_path

        expect(page).to have_content("朝のヨガ")

        # 別タブでの削除を再現する（画面に描画済みの id だけが残る）
        light_time2.destroy!

        find("button", text: ">").click

        aggregate_failures do
          expect(page).to have_content(I18n.t("defaults.flash_message.record_not_found"))
          expect(page).to have_content("朝のヨガ")
        end
      end
    end

    context "キーボード操作（デスクトップ）" do
      before do
        page.driver.browser.manage.window.resize_to(1200, 800)
      end

      it "下キーで次へ切り替えできること" do
        visit mypage_path

        expect(page).to have_content("朝のヨガ")

        find("body").send_keys(:arrow_down)

        expect(page).to have_content("夜の読書")
      end
    end

    context "キーボード操作（モバイル）" do
      before do
        page.driver.browser.manage.window.resize_to(375, 667)
      end

      it "右キーで次へ切り替えできること" do
        visit mypage_path

        expect(page).to have_content("朝のヨガ")

        find("body").send_keys(:arrow_right)

        expect(page).to have_content("夜の読書")
      end
    end
  end

  describe "mypage 表示" do
    context "LightTime が存在しない場合" do
      it "新規登録導線が表示されること" do
        visit mypage_path

        aggregate_failures do
          expect(page).to have_content("登録されていません")

          expect(page).to have_link("新規登録", href: new_light_time_path)
        end
      end
    end

    context "LightTime が1件の場合" do
      before do
        create(:light_time, :current, user: user)
      end

      it "切り替えボタンが表示されないこと" do
        visit mypage_path

        aggregate_failures do
          expect(page).not_to have_button("<")
          expect(page).not_to have_button(">")
        end
      end
    end

    context "LightTime が複数ある場合" do
      before do
        create(:light_time, :current, user: user)
        create(:light_time, user: user)
      end

      it "切り替えボタンが表示されること" do
        visit mypage_path

        aggregate_failures do
          expect(page).to have_button("<")
          expect(page).to have_button(">")
        end
      end
    end
  end
end

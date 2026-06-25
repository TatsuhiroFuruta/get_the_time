require "rails_helper"

RSpec.describe "RegretRecords", type: :system do
  let(:user) { create(:user) }
  # ハンバーガーメニューはマイページに dark_time と light_time の両方がある時のみ表示される
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  before do
    sign_in user
  end

  describe "新規作成" do
    it "新規作成でき、一覧に登録した内容が表示されること" do
      visit new_regret_record_path

      fill_in "タイトル（任意）", with: "ダラダラした日"
      fill_in "後悔した内容", with: "やるべきことに手をつけられなかった"

      click_button "登録する"

      aggregate_failures do
        expect(page).to have_current_path(regret_records_path)
        expect(page).to have_content(
          I18n.t("defaults.flash_message.created", item: RegretRecord.model_name.human)
        )
        expect(page).to have_content("ダラダラした日")
        expect(page).to have_content("やるべきことに手をつけられなかった")
      end
    end

    it "後悔した内容が未入力では作成できないこと" do
      visit new_regret_record_path

      fill_in "後悔した内容", with: ""

      click_button "登録する"

      aggregate_failures do
        expect(page).to have_content(
          I18n.t("defaults.flash_message.not_created", item: RegretRecord.model_name.human)
        )
        expect(page).to have_content("後悔した内容を入力してください")
        expect(page).to have_current_path(new_regret_record_path)
      end
    end

    it "キャンセルで一覧へ戻ること" do
      visit new_regret_record_path

      click_link "キャンセル"

      expect(page).to have_current_path(regret_records_path)
    end
  end

  describe "詳細画面" do
    let!(:regret_record) do
      create(:regret_record, user: user, title: "ダラダラした日", content: "やるべきことに手をつけられなかった")
    end

    it "一覧の記録をクリックすると詳細画面が表示されること" do
      visit regret_records_path

      within('[data-test="regret-records-list"]') do
        click_link "ダラダラした日"
      end

      aggregate_failures do
        expect(page).to have_current_path(regret_record_path(regret_record))
        expect(page).to have_content("後悔した1日の記録詳細")
        expect(page).to have_content("ダラダラした日")
        expect(page).to have_content("やるべきことに手をつけられなかった")
      end
    end

    it "「一覧に戻る」をクリックすると一覧へ戻ること" do
      visit regret_record_path(regret_record)

      click_link "← 一覧に戻る"

      expect(page).to have_current_path(regret_records_path)
    end
  end

  describe "編集" do
    let!(:regret_record) do
      create(:regret_record, user: user, title: "編集前タイトル", content: "編集前の内容")
    end

    it "詳細画面の「編集する」から更新でき、詳細画面に反映されること" do
      visit regret_record_path(regret_record)

      click_link "編集"
      expect(page).to have_current_path(edit_regret_record_path(regret_record))

      fill_in "タイトル（任意）", with: "編集後タイトル"
      fill_in "後悔した内容", with: "編集後の内容"
      click_button "更新する"

      aggregate_failures do
        expect(page).to have_current_path(regret_record_path(regret_record))
        expect(page).to have_content(
          I18n.t("defaults.flash_message.updated", item: RegretRecord.model_name.human)
        )
        expect(page).to have_content("編集後タイトル")
        expect(page).to have_content("編集後の内容")
      end
    end

    it "後悔した内容が未入力では更新できないこと" do
      visit edit_regret_record_path(regret_record)

      fill_in "後悔した内容", with: ""

      click_button "更新する"

      aggregate_failures do
        expect(page).to have_content(
          I18n.t("defaults.flash_message.not_updated", item: RegretRecord.model_name.human)
        )
        expect(page).to have_content("後悔した内容を入力してください")
        expect(page).to have_current_path(edit_regret_record_path(regret_record))
      end
    end

    it "「キャンセル」をクリックすると詳細画面へ戻ること" do
      visit edit_regret_record_path(regret_record)

      click_link "キャンセル"

      expect(page).to have_current_path(regret_record_path(regret_record))
    end
  end

  describe "削除" do
    let!(:regret_record) do
      create(:regret_record, user: user, title: "削除する記録", content: "削除される内容")
    end

    it "詳細画面の「削除」をクリックすると一覧へ遷移し、記録が削除されていること" do
      visit regret_record_path(regret_record)

      accept_confirm do
        click_link "削除"
      end

      aggregate_failures do
        expect(page).to have_current_path(regret_records_path)
        expect(page).to have_content(
          I18n.t("defaults.flash_message.deleted", item: RegretRecord.model_name.human)
        )
        expect(page).not_to have_content("削除する記録")
      end
    end
  end

  describe "お気に入り" do
    context "お気に入りトグル" do
      let!(:regret_record) do
        create(:regret_record, user: user, title: "お気に入り対象", content: "本質的な後悔")
      end

      it "☆ をクリックすると ★ に切り替わり、レコードが favorited になること" do
        visit regret_records_path

        within('[data-test="regret-records-list"]') do
          expect(page).to have_button("お気に入りに追加")
          click_on "お気に入りに追加"
          expect(page).to have_button("お気に入りを解除")
        end

        expect(regret_record.reload.favorited).to be true
      end

      it "★ をクリックすると ☆ に戻り、favorited が false になること" do
        regret_record.update!(favorited: true)
        visit regret_records_path

        within('[data-test="regret-records-list"]') do
          expect(page).to have_button("お気に入りを解除")
          click_on "お気に入りを解除"
          expect(page).to have_button("お気に入りに追加")
        end

        expect(regret_record.reload.favorited).to be false
      end
    end

    context "お気に入りで絞り込みするとき" do
      before do
        create(:regret_record, user: user, title: "お気に入り対象", favorited: true)
        create(:regret_record, user: user, title: "通常レコード", favorited: false)
      end

      it "「★ お気に入り」タブをクリックするとお気に入りのみ表示されること" do
        visit regret_records_path
        click_on "★ お気に入り"

        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).not_to have_content("通常レコード")
        end
      end

      it "「すべて」タブをクリックすると全件表示されること" do
        visit regret_records_path(q: { favorited_eq: true })

        # まずお気に入りのみ表示されていることを確認
        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).not_to have_content("通常レコード")
        end

        click_on "すべて"

        aggregate_failures do
          expect(page).to have_content("お気に入り対象")
          expect(page).to have_content("通常レコード")
        end
      end
    end

    context "お気に入りタブでお気に入りが1件もないとき" do
      before do
        create(:regret_record, user: user, favorited: false)
      end

      it "お気に入り未登録のメッセージが表示されること" do
        visit regret_records_path
        click_on "★ お気に入り"
        expect(page).to have_content("お気に入りの記録がありません。★をクリックして追加できます")
      end
    end
  end

  describe "マイページからの導線" do
    it "「後悔したと思ったら」をクリックすると新規作成フォームが表示されること" do
      visit mypage_path

      # PC用・モバイル用で同じ文言のリンクが2つあるため、実際に表示されている方をクリックする
      # (ignore_hidden_elements = false のため visible: true で可視要素に限定する)
      click_link "後悔したと思ったら", match: :first, visible: true

      aggregate_failures do
        expect(page).to have_current_path(new_regret_record_path)
        expect(page).to have_content("後悔した1日の記録")
      end
    end
  end

  describe "ハンバーガーメニューからの導線" do
    it "「後悔した1日の記録一覧」をクリックすると一覧画面が表示されること" do
      visit mypage_path

      find('[data-hamburger-target="button"]').click

      within('[data-hamburger-target="menu"]') do
        click_on "後悔した1日の記録一覧"
      end

      aggregate_failures do
        expect(page).to have_current_path(regret_records_path)
        expect(page).to have_content("後悔した1日の記録一覧")
      end
    end
  end

  describe "ページネーション" do
    context "記録が10件以上あるとき" do
      before do
        # 10件作成（per_page: 9 を超える件数）
        10.times { |i| create(:regret_record, user: user, content: "後悔#{i + 1}") }
        visit regret_records_path
      end

      it "1ページ目には9件まで表示されること" do
        within('[data-test="regret-records-list"]') do
          expect(page).to have_selector("a", count: 9)
        end
      end

      it "ページネーションリンクが表示されること" do
        expect(page).to have_selector('[data-test="pagination"]')
      end

      it "2ページ目をクリックすると残りのレコードが表示されること" do
        click_on "2"

        aggregate_failures do
          expect(page).to have_current_path(regret_records_path, ignore_query: true)
          # created_at: desc 順なので、最初に作った「後悔1」が2ページ目に来る
          expect(page).to have_content("後悔1")
        end
      end
    end

    context "記録が9件以下のとき" do
      before do
        9.times { create(:regret_record, user: user) }
        visit regret_records_path
      end

      it "ページネーションリンクが表示されないこと" do
        expect(page).not_to have_selector('[data-test="pagination"]')
      end
    end
  end

  describe "一覧画面からの導線" do
    it "「後悔した1日を投稿」をクリックすると新規作成フォームが表示されること" do
      visit regret_records_path

      click_link "後悔した1日を投稿"

      expect(page).to have_current_path(new_regret_record_path)
    end

    it "記録がない場合は案内文が表示されること" do
      visit regret_records_path

      expect(page).to have_content("後悔した1日の記録がまだありません")
    end
  end
end

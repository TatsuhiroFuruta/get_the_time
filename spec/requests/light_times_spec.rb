require 'rails_helper'

RSpec.describe "LightTimes", type: :request do
  let(:user) { create(:user) }
  let(:other_user) { create(:user) }

  before do
    sign_in user
  end

  # 共通化した shared_examples
  shared_examples '他人の LightTime にアクセスできないこと' do |http_method|
    it "他人の LightTime にアクセスできないこと" do
      other_light_time = create(:light_time, user: other_user)
      expect {
        send(http_method, light_time_path(other_light_time))
      }.to raise_error(ActiveRecord::RecordNotFound)
    end
  end

  describe 'GET /light_times/new' do
    it '新規作成ページが表示されること' do
      get new_light_time_path
      expect(response).to have_http_status(:ok)
    end

    it '@light_time が新規インスタンスであること' do
      get new_light_time_path
      expect(assigns(:light_time)).to be_a_new(LightTime)
    end
  end

  describe 'POST /light_times' do
    context '正常系' do
      let(:valid_params) do
        {
          light_time: {
            action: "朝のヨガ",
            desired_self: "穏やかな自分",
            characteristic: "リラックス効果"
          }
        }
      end

      it 'LightTime が作成されること' do
        expect {
          post light_times_path, params: valid_params
        }.to change(user.light_times, :count).by(1)
      end

      it '作成された LightTime が current になること' do
        post light_times_path, params: valid_params
        expect(LightTime.last.is_current).to be true
      end

      it '作成後にマイページへリダイレクトされること' do
        post light_times_path, params: valid_params
        expect(response).to redirect_to(mypage_path)
      end

      it 'フラッシュメッセージが表示されること' do
        post light_times_path, params: valid_params
        expect(flash[:notice]).to be_present
      end

      context '既存の current な LightTime がある場合' do
        let!(:current_light_time) { create(:light_time, :current, user: user) }

        it '既存の current が false になること' do
          post light_times_path, params: valid_params
          expect(current_light_time.reload.is_current).to be false
        end

        it '新しい LightTime が current になること' do
          post light_times_path, params: valid_params
          expect(LightTime.last.is_current).to be true
        end
      end
    end

    context '異常系' do
      let(:invalid_params) do
        {
          light_time: {
            action: "",
            desired_self: "穏やかな自分"
          }
        }
      end

      it 'LightTime が作成されないこと' do
        expect {
          post light_times_path, params: invalid_params
        }.not_to change(LightTime, :count)
      end

      it 'new テンプレートが再表示されること' do
        post light_times_path, params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:new)
      end

      it 'エラーメッセージが表示されること' do
        post light_times_path, params: invalid_params
        expect(flash[:alert]).to be_present
      end
    end
  end

  describe 'GET /light_times/:id' do
    let(:light_time) { create(:light_time, user: user) }

    it '詳細ページが表示されること' do
      get light_time_path(light_time)
      expect(response).to have_http_status(:ok)
    end

    include_examples '他人の LightTime にアクセスできないこと', :get
  end

  describe 'GET /light_times/:id/edit' do
    let(:light_time) { create(:light_time, user: user) }

    it '編集ページが表示されること' do
      get edit_light_time_path(light_time)
      expect(response).to have_http_status(:ok)
    end

    include_examples '他人の LightTime にアクセスできないこと', :get
  end

  describe 'PATCH /light_times/:id' do
    let(:light_time) { create(:light_time, user: user, action: "朝のランニング") }

    context '正常系' do
      let(:update_params) do
        {
          light_time: {
            action: "夜のランニング",
            desired_self: "健康的な自分"
          }
        }
      end

      it 'LightTime が更新されること' do
        patch light_time_path(light_time), params: update_params
        expect(light_time.reload.action).to eq "夜のランニング"
      end

      it '詳細ページへリダイレクトされること' do
        patch light_time_path(light_time), params: update_params
        expect(response).to redirect_to(light_time_path(light_time))
      end

      it 'フラッシュメッセージが表示されること' do
        patch light_time_path(light_time), params: update_params
        expect(flash[:notice]).to be_present
      end
    end

    context '異常系' do
      let(:invalid_params) do
        {
          light_time: {
            action: ""
          }
        }
      end

      it 'LightTime が更新されないこと' do
        patch light_time_path(light_time), params: invalid_params
        expect(light_time.reload.action).to eq "朝のランニング"
      end

      it 'edit テンプレートが再表示されること' do
        patch light_time_path(light_time), params: invalid_params
        expect(response).to have_http_status(:unprocessable_entity)
        expect(response).to render_template(:edit)
      end

      it 'エラーメッセージが表示されること' do
        patch light_time_path(light_time), params: invalid_params
        expect(flash[:alert]).to be_present
      end
    end

    context '他人の LightTime' do
      let(:other_light_time) { create(:light_time, user: other_user) }

      it '更新できないこと' do
        expect {
          patch light_time_path(other_light_time), params: { light_time: { action: "更新" } }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end
    end
  end

  describe 'DELETE /light_times/:id' do
    context '正常系' do
      let!(:light_time) { create(:light_time, user: user, action: "朝のランニング") }

      it 'LightTime が削除されること' do
        expect {
          delete light_time_path(light_time)
        }.to change(user.light_times, :count).by(-1)
      end

      it 'マイページへリダイレクトされること' do
        delete light_time_path(light_time)
        expect(response).to redirect_to(mypage_path)
      end

      it 'フラッシュメッセージが表示されること' do
        delete light_time_path(light_time)
        expect(flash[:notice]).to be_present
      end

      context '削除対象が current の場合' do
        let!(:current_light_time) { create(:light_time, :current, user: user, action: "朝のヨガ") }
        let!(:next_light_time) { create(:light_time, user: user, action: "夜の読書") }

        it 'current な LightTime が削除されること' do
          expect {
            delete light_time_path(current_light_time)
          }.to change(user.light_times, :count).by(-1)
        end

        it '次の LightTime が current になること' do
          delete light_time_path(current_light_time)
          expect(next_light_time.reload.is_current).to be true
        end

        it '作成日時が最も古い LightTime が current になること' do
          # トレイトを使って作成日時を指定
          oldest_light_time = create(:light_time, :old, user: user, action: "最も古い")
          newer_light_time = create(:light_time, :recent, user: user, action: "新しい")

          delete light_time_path(current_light_time)
          expect(oldest_light_time.reload.is_current).to be true
          expect(newer_light_time.reload.is_current).to be false
        end
      end

      context '削除対象が current でない場合' do
        let!(:current_light_time) { create(:light_time, :current, user: user, action: "朝のヨガ") }
        let!(:non_current_light_time) { create(:light_time, user: user, action: "夜の読書") }

        it 'current な LightTime は変わらないこと' do
          delete light_time_path(non_current_light_time)
          expect(current_light_time.reload.is_current).to be true
        end
      end

      context 'current を削除して LightTime が0件になる場合' do
        let!(:only_light_time) { create(:light_time, :current, user: user, action: "唯一の LightTime") }

        it 'LightTime が削除されること' do
          expect {
            delete light_time_path(only_light_time)
          }.to change(user.light_times, :count).by(-1)
        end

        it 'エラーにならないこと' do
          expect {
            delete light_time_path(only_light_time)
          }.not_to raise_error
        end
      end
    end

    context '異常系' do
      include_examples '他人の LightTime にアクセスできないこと', :delete
    end
  end

  describe 'PATCH /light_times/:id/switch' do
    let!(:light_time1) { create(:light_time, :current, user: user, action: "朝の運動") }
    let!(:light_time2) { create(:light_time, user: user, action: "夜の読書") }
    let!(:light_time3) { create(:light_time, user: user, action: "昼の瞑想") }

    context '正常系' do
      before do
        patch switch_light_time_path(light_time2), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end

      it 'Turbo Stream レスポンスが返されること' do
        expect(response.content_type).to include('text/vnd.turbo-stream.html')
      end

      it '指定した LightTime が current になること' do
        expect(light_time2.reload.is_current).to be true
      end

      it '他の LightTime が current でなくなること' do
        expect(light_time1.reload.is_current).to be false
        expect(light_time3.reload.is_current).to be false
      end

      it '同じユーザーの LightTime のみ影響を受けること' do
        other_user_light_time = create(:light_time, :current, user: other_user, action: "他人の習慣")

        expect(other_user_light_time.reload.is_current).to be true
      end
    end

    context '異常系' do
      it '存在しない LightTime ID の場合は RecordNotFound が発生すること' do
        expect {
          patch switch_light_time_path(id: 99999), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it '他人の LightTime には切り替えられないこと' do
        other_light_time = create(:light_time, user: other_user)
        expect {
          patch switch_light_time_path(other_light_time), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
        }.to raise_error(ActiveRecord::RecordNotFound)
      end

      it 'ログインしていない場合、リダイレクトされること' do
        sign_out user

        patch switch_light_time_path(light_time2), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response).to have_http_status(:redirect)
        expect(response).to redirect_to(user_session_path)
      end
    end

    context 'Turbo Stream のレスポンス内容' do
      before do
        patch switch_light_time_path(light_time2), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }
      end

      it 'レスポンスに turbo-stream タグが含まれること' do
        expect(response.body).to include('turbo-stream')
      end

      it 'レスポンスに replace アクションが含まれること' do
        expect(response.body).to include('action="replace"')
      end

      it '切り替え後の LightTime の内容が含まれること' do
        expect(response.body).to include('夜の読書')
      end
    end

    context 'LightTime が1件のみの場合' do
      let(:user_with_one) { create(:user) }
      let!(:only_light_time) { create(:light_time, :current, user: user_with_one, action: '唯一の習慣') }

      before do
        sign_in user_with_one
      end

      it '切り替えても同じ LightTime のままであること' do
        patch switch_light_time_path(only_light_time), headers: { 'Accept' => 'text/vnd.turbo-stream.html' }

        expect(response).to have_http_status(:ok)
        expect(only_light_time.reload.is_current).to be true
      end
    end
  end
end

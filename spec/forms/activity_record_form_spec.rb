require 'rails_helper'

RSpec.describe ActivityRecordForm, type: :model do
  let(:user)        { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }
  let!(:dark_time)  { create(:dark_time, user: user) }

  let(:valid_attributes) do
    {
      started_at:                1.hour.ago,
      ended_at:                  Time.current,
      total_duration:            60,
      idle_duration:             5,
      satisfaction:              3,
      progress:                  3,
      quality:                   3,
      focus:                     3,
      fatigue:                   3,
      task:                      'RSpec を書く',
      comment:                   'テストコメント',
      light_time_id:             light_time.id,
      light_time_characteristic: '集中しやすい朝の時間',
      dark_time_characteristic:  'スマホを見てしまう時間'
    }
  end

  subject(:form) { described_class.new(valid_attributes) }

  # =========================================================
  # バリデーション
  # =========================================================
  describe 'バリデーション' do
    context '正常な値のとき' do
      it '有効であること' do
        expect(form).to be_valid
      end
    end

    describe 'idle_duration' do
      it '負の値は無効' do
        form.idle_duration = -1
        expect(form).to be_invalid
        expect(form.errors[:idle_duration]).to be_present
      end

      it 'total_duration を超えると無効' do
        form.idle_duration = form.total_duration + 1
        expect(form).to be_invalid
        expect(form.errors[:idle_duration]).to include('は合計時間以下にしてください')
      end

      it 'total_duration と同値は有効' do
        form.idle_duration = form.total_duration
        expect(form).to be_valid
      end
    end

    describe '5段階評価カラム' do
      %i[satisfaction progress quality focus fatigue].each do |attr|
        context attr.to_s do
          it '0 は無効' do
            form.send(:"#{attr}=", 0)
            expect(form).to be_invalid
            expect(form.errors[attr]).to be_present
          end

          it '6 は無効' do
            form.send(:"#{attr}=", 6)
            expect(form).to be_invalid
            expect(form.errors[attr]).to be_present
          end

          it '3 は有効' do
            form.send(:"#{attr}=", 3)
            expect(form).to be_valid
          end
        end
      end
    end
  end

  # =========================================================
  # #save
  # =========================================================
  describe '#save' do
    context '正常な値のとき' do
      it 'true を返すこと' do
        expect(form.save(user)).to be true
      end

      it 'ActivityRecord が 1 件作成されること' do
        expect { form.save(user) }.to change(ActivityRecord, :count).by(1)
      end

      it '作成された ActivityRecord の各値が正しいこと' do
        form.save(user)
        activity_record = ActivityRecord.last
        aggregate_failures do
          expect(activity_record.task).to           eq 'RSpec を書く'
          expect(activity_record.comment).to        eq 'テストコメント'
          expect(activity_record.total_duration).to eq 60
          expect(activity_record.idle_duration).to  eq 5
          expect(activity_record.satisfaction).to   eq 3
          expect(activity_record.light_time).to     eq light_time
        end
      end

      it 'LightTime の characteristic が更新されること' do
        form.save(user)
        expect(light_time.reload.characteristic).to eq '集中しやすい朝の時間'
      end

      it 'DarkTime の characteristic が更新されること' do
        form.save(user)
        expect(dark_time.reload.characteristic).to eq 'スマホを見てしまう時間'
      end

      context 'light_time_characteristic が空文字のとき' do
        before { form.light_time_characteristic = '' }

        it 'LightTime の characteristic が空文字に更新されること' do
          form.save(user)
          expect(light_time.reload.characteristic).to eq ''
        end
      end
    end

    context 'バリデーションエラーのとき（satisfaction = 0）' do
      before { form.satisfaction = 0 }

      it 'false を返すこと' do
        expect(form.save(user)).to be false
      end

      it 'ActivityRecord が作成されないこと' do
        expect { form.save(user) }.not_to change(ActivityRecord, :count)
      end

      it 'LightTime が更新されないこと' do
        original = light_time.characteristic
        form.save(user)
        expect(light_time.reload.characteristic).to eq original
      end
    end

    context 'light_time_id が nil のとき' do
      before { form.light_time_id = nil }

      it 'save が false を返すこと' do
        expect(form.save(user)).to be false
      end

      it 'ActivityRecord が作成されないこと' do
        expect { form.save(user) }.not_to change(ActivityRecord, :count)
      end
    end
  end
end

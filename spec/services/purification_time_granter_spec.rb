require "rails_helper"

RSpec.describe PurificationTimeGranter, type: :service do
  let(:user) { create(:user) }

  subject(:granter) { described_class.new(user) }

  # 付与分数は乱数（重み付き抽選）なので、テストでは 1 ブロック 10 分に固定する
  before { allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10) }

  describe "#call" do
    context "PurificationTime が既に存在するとき" do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      context "90 分（3 ブロック）のとき" do
        it "remaining_time に 1800 秒 (3 ブロック × 10 分) 加算され、付与分数 30 を返すこと" do
          aggregate_failures do
            expect(granter.call(90)).to eq 30
            expect(purification_time.reload.remaining_time).to eq 1800
          end
        end
      end

      context "20 分（30 未満）のとき" do
        it "remaining_time が変化せず、0 を返すこと" do
          aggregate_failures do
            expect(granter.call(20)).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end
    end

    context "PurificationTime がまだ存在しないとき" do
      context "90 分（3 ブロック）のとき" do
        it "PurificationTime が新規作成されて 1800 秒セットされること" do
          aggregate_failures do
            expect { granter.call(90) }.to change(PurificationTime, :count).by(1)
            expect(user.reload.purification_time.remaining_time).to eq 1800
          end
        end
      end

      context "20 分（30 未満）のとき" do
        it "PurificationTime は作成されず、0 を返すこと" do
          aggregate_failures do
            expect { granter.call(20) }.not_to change(PurificationTime, :count)
            expect(granter.call(20)).to eq 0
          end
        end
      end
    end
  end
end

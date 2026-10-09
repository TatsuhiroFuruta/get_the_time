require "rails_helper"

RSpec.describe PurificationReward, type: :model do
  # =========================================================
  # .sample_minutes
  # =========================================================
  describe ".sample_minutes" do
    subject { described_class.sample_minutes }

    [
      [ 0,  8 ],
      [ 59, 8 ],
      [ 60, 10 ],
      [ 89, 10 ],
      [ 90, 13 ],
      [ 98, 13 ],
      [ 99, 15 ]
    ].each do |rand_val, expected|
      context "rand が #{rand_val} を返すとき" do
        before { allow(described_class).to receive(:rand).with(100).and_return(rand_val) }

        it "#{expected} 分を返すこと" do
          is_expected.to eq expected
        end
      end
    end

    it "スタブなしでも有効な付与分数を返すこと" do
      is_expected.to be_in([ 8, 10, 13, 15 ])
    end
  end

  # =========================================================
  # .blocks
  # =========================================================
  describe ".blocks" do
    subject { described_class.blocks(minutes) }

    context "nil のとき" do
      let(:minutes) { nil }
      it { is_expected.to eq 0 }
    end

    context "0 分のとき" do
      let(:minutes) { 0 }
      it { is_expected.to eq 0 }
    end

    context "29 分のとき" do
      let(:minutes) { 29 }
      it { is_expected.to eq 0 }
    end

    context "30 分のとき" do
      let(:minutes) { 30 }
      it { is_expected.to eq 1 }
    end

    context "59 分のとき" do
      let(:minutes) { 59 }
      it { is_expected.to eq 1 }
    end

    context "60 分のとき" do
      let(:minutes) { 60 }
      it { is_expected.to eq 2 }
    end

    context "265 分（4 時間 25 分）のとき" do
      let(:minutes) { 265 }
      it { is_expected.to eq 8 }
    end

    context "負の値のとき" do
      let(:minutes) { -5 }

      # Ruby の整数除算は負の無限大方向に丸まる（-5 / 30 == -1）ため、
      # ガードがないとブロック数が水増しされる
      it { is_expected.to eq 0 }
    end
  end

  # =========================================================
  # .sample_minutes_for
  # =========================================================
  describe ".sample_minutes_for" do
    subject { described_class.sample_minutes_for(blocks) }

    before { allow(described_class).to receive(:sample_minutes).and_return(10) }

    context "0 ブロックのとき" do
      let(:blocks) { 0 }

      it { is_expected.to eq 0 }

      it "抽選を引かないこと" do
        subject
        expect(described_class).not_to have_received(:sample_minutes)
      end
    end

    context "負のブロック数のとき" do
      let(:blocks) { -1 }
      it { is_expected.to eq 0 }
    end

    context "1 ブロックのとき" do
      let(:blocks) { 1 }

      it { is_expected.to eq 10 }

      it "抽選を 1 回引くこと" do
        subject
        expect(described_class).to have_received(:sample_minutes).once
      end
    end

    context "3 ブロックのとき" do
      let(:blocks) { 3 }

      it { is_expected.to eq 30 }

      it "抽選を 3 回引くこと" do
        subject
        expect(described_class).to have_received(:sample_minutes).exactly(3).times
      end
    end

    context "スタブなしで 2 ブロックのとき" do
      before { allow(described_class).to receive(:sample_minutes).and_call_original }
      let(:blocks) { 2 }

      it "抽選 2 回分の合計になること" do
        is_expected.to be_between(16, 30)
      end
    end
  end

  # =========================================================
  # .minutes_until_next
  # =========================================================
  describe ".minutes_until_next" do
    subject { described_class.minutes_until_next(total_minutes, granted_blocks) }

    context "nil のとき" do
      let(:total_minutes)  { nil }
      let(:granted_blocks) { 0 }
      it { is_expected.to eq 30 }
    end

    context "累計 0 分・付与済み 0 ブロックのとき" do
      let(:total_minutes)  { 0 }
      let(:granted_blocks) { 0 }
      it { is_expected.to eq 30 }
    end

    context "累計 25 分・付与済み 0 ブロックのとき" do
      let(:total_minutes)  { 25 }
      let(:granted_blocks) { 0 }
      it { is_expected.to eq 5 }
    end

    context "累計 30 分・付与済み 1 ブロック（ちょうど付与された直後）のとき" do
      let(:total_minutes)  { 30 }
      let(:granted_blocks) { 1 }

      it "次のブロックまでの 30 分を返すこと" do
        is_expected.to eq 30
      end
    end

    context "累計 265 分・付与済み 8 ブロックのとき" do
      let(:total_minutes)  { 265 }
      let(:granted_blocks) { 8 }
      it { is_expected.to eq 5 }
    end

    # 活動記録を削除すると累計だけが下がる。累計しか見ないと「あと 30 分」と出るが、
    # 30 分ぶんはすでに払い出しているので、実際に次の 1 ブロックまでは 60 分必要になる。
    context "削除で累計が 0 に戻り、付与済みが 1 ブロック残っているとき" do
      let(:total_minutes)  { 0 }
      let(:granted_blocks) { 1 }

      it "払い出し済みの分を含めた残り 60 分を返すこと" do
        is_expected.to eq 60
      end
    end

    # 付与を経ずに活動記録だけが積まれた状態（seeds など）。すでに閾値を越えているので
    # 次の保存で払い出される。負の分数は表示しない。
    context "累計が次の閾値を越えているのに付与済みが 0 のとき" do
      let(:total_minutes)  { 70 }
      let(:granted_blocks) { 0 }

      it "0 で止まること" do
        is_expected.to eq 0
      end
    end

    context "付与済みブロック数を省略したとき" do
      subject { described_class.minutes_until_next(25) }

      it "0 ブロック扱いになること" do
        is_expected.to eq 5
      end
    end
  end
end

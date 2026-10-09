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

  # =========================================================
  # .grant!
  # =========================================================
  describe ".grant!" do
    let(:user)        { create(:user) }
    let!(:light_time) { create(:light_time, :current, user: user) }

    # 付与分数は乱数（重み付き抽選）なので、テストでは 1 ブロック 10 分に固定する
    before { allow(PurificationReward).to receive(:sample_minutes).and_return(10) }

    # grant! は保存済みのレコードを受け取る。started_at は ended_at から逆算する。
    def create_record(total_duration, ended_at: Time.current, started_at: nil)
      create(:activity_record,
             user:           user,
             light_time:     light_time,
             total_duration: total_duration,
             started_at:     started_at || (ended_at - total_duration.minutes),
             ended_at:       ended_at)
    end

    context "PurificationTime が既に存在するとき" do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      context "当日累計が 30 分に満たないとき" do
        it "付与されず 0 を返すこと" do
          aggregate_failures do
            expect(described_class.grant!(user, create_record(25))).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end

      context "25 分を 2 回記録したとき" do
        it "2 回目で 1 ブロック付与されること" do
          first  = described_class.grant!(user, create_record(25))
          second = described_class.grant!(user, create_record(25))

          aggregate_failures do
            expect(first).to eq 0
            expect(second).to eq 10
            expect(purification_time.reload.remaining_time).to eq 600
          end
        end
      end

      context "累計 50 分の状態で 90 分を記録したとき" do
        before do
          described_class.grant!(user, create_record(25))
          described_class.grant!(user, create_record(25))
        end

        it "累計 140 分となり 3 ブロック付与されること" do
          # floor(140/30) - floor(50/30) = 4 - 1 = 3 ブロック
          aggregate_failures do
            expect(described_class.grant!(user, create_record(90))).to eq 30
            expect(purification_time.reload.remaining_time).to eq 600 + 1800
          end
        end
      end

      context "1 件で複数ブロックをまたぐとき" do
        it "またいだ数だけ抽選が引かれること" do
          described_class.grant!(user, create_record(90))
          expect(PurificationReward).to have_received(:sample_minutes).exactly(3).times
        end
      end

      context "日付が変わったとき" do
        it "累計がリセットされ、前日の 25 分が持ち越されないこと" do
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            described_class.grant!(user, create_record(25))
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 10, 0, 0)) do
            described_class.grant!(user, create_record(25))
          end

          aggregate_failures do
            expect(granted).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end

      context "0 時をまたぐセッションのとき" do
        it "前日に余りがあってもセッション単体で 30 分ごとに付与されること" do
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            described_class.grant!(user, create_record(25))  # 前日累計 25 分・付与 0
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 0, 20, 0)) do
            described_class.grant!(user,
              create_record(30,
                            started_at: Time.zone.local(2026, 9, 8, 23, 45, 0),
                            ended_at:   Time.zone.local(2026, 9, 9, 0, 15, 0))
            )
          end

          expect(granted).to eq 10
        end
      end

      # created_at（送信時刻）と ended_at（活動の終了時刻）が別の日に割れるケース。
      # ここが割れないと created_at 基準の実装でも同じ結果になってしまい、
      # ACTIVITY_AT を導入した意味を検証できない。
      context "活動が終わった翌日に記録を送信したとき" do
        it "送信日ではなく終了日の累計に合算されて付与されること" do
          # 前日（9/8）の 22:00 までに 25 分の記録がある
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            described_class.grant!(user, create_record(25))
          end

          # 9/8 23:50 に終わった 25 分の活動を、日付をまたいだ 9/9 00:05 に送信する
          granted = travel_to(Time.zone.local(2026, 9, 9, 0, 5, 0)) do
            record = create_record(25, ended_at: Time.zone.local(2026, 9, 8, 23, 50, 0))
            record.update_column(:created_at, Time.zone.local(2026, 9, 9, 0, 5, 0))
            described_class.grant!(user, record.reload)
          end

          # 9/8 の累計 50 分となり 1 ブロック付与される。
          # created_at 基準だと 9/9 の累計 25 分となり付与 0 になる。
          aggregate_failures do
            expect(granted).to eq 10
            expect(ActivityRecord.total_light_time_on(user, Date.new(2026, 9, 8))).to eq 50
            expect(ActivityRecord.total_light_time_on(user, Date.new(2026, 9, 9))).to eq 0
          end
        end
      end

      context "ended_at が NULL のとき" do
        it "created_at の日で累計されて付与されること" do
          record = create_record(30)
          record.update_column(:ended_at, nil)

          expect(described_class.grant!(user, record.reload)).to eq 10
        end
      end

      # 当日累計はレコードから導出するため削除で減る。付与済みブロック数まで
      # 導出に頼ると、29 分ためた状態で 1 分の記録を作っては消す操作で
      # 1 分ごとに 1 ブロック稼げてしまう。
      context "記録を削除して作り直したとき" do
        before do
          described_class.grant!(user, create_record(29))  # 累計 29 分・付与 0
        end

        it "同じ 1 分の記録を作り直しても 2 回目以降は付与されないこと" do
          first_record = create_record(1)
          first_granted = described_class.grant!(user, first_record)
          first_record.destroy!  # 累計 29 分に戻る

          second_record = create_record(1)
          second_granted = described_class.grant!(user, second_record)
          second_record.destroy!

          third_granted = described_class.grant!(user, create_record(1))

          aggregate_failures do
            expect(first_granted).to  eq 10  # 29 + 1 = 30 分ぶんの正当な付与
            expect(second_granted).to eq 0
            expect(third_granted).to  eq 0
            expect(purification_time.reload.remaining_time).to eq 600
          end
        end

        it "削除後は付与済みの分を取り戻すまで付与されないこと" do
          described_class.grant!(user, create_record(1))  # 累計 30 分 → 1 ブロック付与

          user.activity_records.destroy_all  # 累計 0 分。付与済み 1 ブロックは残る

          aggregate_failures do
            # 30 分ぶんはすでに払い出しているので、次の 1 ブロックには 60 分必要
            expect(described_class.grant!(user, create_record(30))).to eq 0
            expect(described_class.grant!(user, create_record(30))).to eq 10
          end
        end
      end

      context "浄化タイマーをリセットしたとき" do
        it "払い出し済みの分は再付与されないこと" do
          described_class.grant!(user, create_record(30))  # 1 ブロック付与
          purification_time.reload.reset!  # 残り時間を 0 に戻す

          # 累計 30 分・付与済み 1 ブロックのままなので、次は 60 分必要
          expect(described_class.grant!(user, create_record(25))).to eq 0
        end
      end
    end

    # #282: running 中に remaining_time だけへ加算すると、stop! が total_time から
    # 残りを計算し直すため付与分が消えていた
    context "浄化タイマーが running のとき" do
      let!(:purification_time) do
        create(:purification_time, user: user,
                                   status: :running, remaining_time: 600, total_time: 600,
                                   started_at: Time.zone.local(2026, 9, 9, 10, 0, 0))
      end

      it "計測中に付与された分が stop! 後も残ること" do
        travel_to(Time.zone.local(2026, 9, 9, 10, 4, 0)) do
          described_class.grant!(user, create_record(30))
        end

        travel_to(Time.zone.local(2026, 9, 9, 10, 6, 0)) do
          purification_time.reload.stop!
        end

        # 600 + 600 - 360 = 840 秒
        expect(purification_time.reload.remaining_time).to eq 840
      end

      it "期限切れのまま残ったタイマーに付与された分が stop! 後も残ること" do
        travel_to(Time.zone.local(2026, 9, 9, 11, 0, 0)) do
          described_class.grant!(user, create_record(30))
        end

        travel_to(Time.zone.local(2026, 9, 9, 11, 5, 0)) do
          purification_time.reload.stop!
        end

        aggregate_failures do
          expect(purification_time.reload.remaining_time).to eq 600
          expect(purification_time).to be_idle
        end
      end

      it "期限切れのタイマーに付与しても払い出し台帳が更新され、同じブロックを再付与しないこと" do
        travel_to(Time.zone.local(2026, 9, 9, 11, 0, 0)) do
          first  = described_class.grant!(user, create_record(30))
          second = described_class.grant!(user, create_record(1))

          aggregate_failures do
            expect(first).to eq 10
            expect(second).to eq 0
            expect(purification_time.reload.granted_blocks_for(Date.new(2026, 9, 9))).to eq 1
          end
        end
      end

      it "計測中に付与した直後も remaining_time と total_time が等しいこと（画面表示とサーバーの残りが一致する）" do
        travel_to(Time.zone.local(2026, 9, 9, 10, 4, 0)) do
          described_class.grant!(user, create_record(30))
        end

        purification_time.reload
        aggregate_failures do
          expect(purification_time.remaining_time).to eq 1200
          expect(purification_time.total_time).to eq 1200
          expect(purification_time).to be_running
        end
      end
    end

    context "PurificationTime がまだ存在しないとき" do
      context "1 ブロック分たまったとき" do
        it "PurificationTime が新規作成されて 600 秒セットされること" do
          record = create_record(30)

          aggregate_failures do
            expect { described_class.grant!(user, record) }.to change(PurificationTime, :count).by(1)
            expect(user.reload.purification_time.remaining_time).to eq 600
          end
        end
      end

      context "当日累計が 30 分に満たないとき" do
        it "PurificationTime は作成されず 0 を返すこと" do
          record = create_record(20)

          aggregate_failures do
            expect { described_class.grant!(user, record) }.not_to change(PurificationTime, :count)
            expect(described_class.grant!(user, record)).to eq 0
          end
        end
      end
    end
  end
end

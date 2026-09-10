require "rails_helper"

RSpec.describe PurificationTimeGranter, type: :service do
  let(:user)        { create(:user) }
  let!(:light_time) { create(:light_time, :current, user: user) }

  subject(:granter) { described_class.new(user) }

  # 付与分数は乱数（重み付き抽選）なので、テストでは 1 ブロック 10 分に固定する
  before { allow(ActivityRecord).to receive(:sample_purification_minutes).and_return(10) }

  # Granter は保存済みのレコードを受け取る。started_at は ended_at から逆算する。
  def create_record(total_duration, ended_at: Time.current, started_at: nil)
    create(:activity_record,
           user:           user,
           light_time:     light_time,
           total_duration: total_duration,
           started_at:     started_at || (ended_at - total_duration.minutes),
           ended_at:       ended_at)
  end

  describe "#call" do
    context "PurificationTime が既に存在するとき" do
      let!(:purification_time) { create(:purification_time, user: user, remaining_time: 0) }

      context "当日累計が 30 分に満たないとき" do
        it "付与されず 0 を返すこと" do
          aggregate_failures do
            expect(granter.call(create_record(25))).to eq 0
            expect(purification_time.reload.remaining_time).to eq 0
          end
        end
      end

      context "25 分を 2 回記録したとき" do
        it "2 回目で 1 ブロック付与されること" do
          first  = granter.call(create_record(25))
          second = granter.call(create_record(25))

          aggregate_failures do
            expect(first).to eq 0
            expect(second).to eq 10
            expect(purification_time.reload.remaining_time).to eq 600
          end
        end
      end

      context "累計 50 分の状態で 90 分を記録したとき" do
        before do
          granter.call(create_record(25))
          granter.call(create_record(25))
        end

        it "累計 140 分となり 3 ブロック付与されること" do
          # floor(140/30) - floor(50/30) = 4 - 1 = 3 ブロック
          aggregate_failures do
            expect(granter.call(create_record(90))).to eq 30
            expect(purification_time.reload.remaining_time).to eq 600 + 1800
          end
        end
      end

      context "1 件で複数ブロックをまたぐとき" do
        it "またいだ数だけ抽選が引かれること" do
          granter.call(create_record(90))
          expect(ActivityRecord).to have_received(:sample_purification_minutes).exactly(3).times
        end
      end

      context "日付が変わったとき" do
        it "累計がリセットされ、前日の 25 分が持ち越されないこと" do
          travel_to(Time.zone.local(2026, 9, 8, 22, 0, 0)) do
            granter.call(create_record(25))
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 10, 0, 0)) do
            granter.call(create_record(25))
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
            granter.call(create_record(25))  # 前日累計 25 分・付与 0
          end

          granted = travel_to(Time.zone.local(2026, 9, 9, 0, 20, 0)) do
            granter.call(
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
            granter.call(create_record(25))
          end

          # 9/8 23:50 に終わった 25 分の活動を、日付をまたいだ 9/9 00:05 に送信する
          granted = travel_to(Time.zone.local(2026, 9, 9, 0, 5, 0)) do
            record = create_record(25, ended_at: Time.zone.local(2026, 9, 8, 23, 50, 0))
            record.update_column(:created_at, Time.zone.local(2026, 9, 9, 0, 5, 0))
            granter.call(record.reload)
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

          expect(granter.call(record.reload)).to eq 10
        end
      end

      # 当日累計はレコードから導出するため削除で減る。付与済みブロック数まで
      # 導出に頼ると、29 分ためた状態で 1 分の記録を作っては消す操作で
      # 1 分ごとに 1 ブロック稼げてしまう。
      context "記録を削除して作り直したとき" do
        before do
          granter.call(create_record(29))  # 累計 29 分・付与 0
        end

        it "同じ 1 分の記録を作り直しても 2 回目以降は付与されないこと" do
          first_record = create_record(1)
          first_granted = granter.call(first_record)
          first_record.destroy!  # 累計 29 分に戻る

          second_record = create_record(1)
          second_granted = granter.call(second_record)
          second_record.destroy!

          third_granted = granter.call(create_record(1))

          aggregate_failures do
            expect(first_granted).to  eq 10  # 29 + 1 = 30 分ぶんの正当な付与
            expect(second_granted).to eq 0
            expect(third_granted).to  eq 0
            expect(purification_time.reload.remaining_time).to eq 600
          end
        end

        it "削除後は付与済みの分を取り戻すまで付与されないこと" do
          granter.call(create_record(1))  # 累計 30 分 → 1 ブロック付与

          user.activity_records.destroy_all  # 累計 0 分。付与済み 1 ブロックは残る

          aggregate_failures do
            # 30 分ぶんはすでに払い出しているので、次の 1 ブロックには 60 分必要
            expect(granter.call(create_record(30))).to eq 0
            expect(granter.call(create_record(30))).to eq 10
          end
        end
      end

      context "浄化タイマーをリセットしたとき" do
        it "払い出し済みの分は再付与されないこと" do
          granter.call(create_record(30))  # 1 ブロック付与
          purification_time.reload.reset!  # 残り時間を 0 に戻す

          # 累計 30 分・付与済み 1 ブロックのままなので、次は 60 分必要
          expect(granter.call(create_record(25))).to eq 0
        end
      end
    end

    context "PurificationTime がまだ存在しないとき" do
      context "1 ブロック分たまったとき" do
        it "PurificationTime が新規作成されて 600 秒セットされること" do
          record = create_record(30)

          aggregate_failures do
            expect { granter.call(record) }.to change(PurificationTime, :count).by(1)
            expect(user.reload.purification_time.remaining_time).to eq 600
          end
        end
      end

      context "当日累計が 30 分に満たないとき" do
        it "PurificationTime は作成されず 0 を返すこと" do
          record = create_record(20)

          aggregate_failures do
            expect { granter.call(record) }.not_to change(PurificationTime, :count)
            expect(granter.call(record)).to eq 0
          end
        end
      end
    end
  end
end

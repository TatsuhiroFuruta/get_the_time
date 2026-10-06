require "rails_helper"

RSpec.describe PurificationTime, type: :model do
  # =========================================================
  # アソシエーション
  # =========================================================
  describe "アソシエーション" do
    it "User に属していること" do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end

  # =========================================================
  # enum
  # =========================================================
  describe "enum status" do
    it "idle / running / paused が定義されていること" do
      expect(described_class.statuses).to eq(
        "idle" => 0, "running" => 1, "paused" => 2
      )
    end
  end

  # =========================================================
  # #finished?
  # =========================================================
  describe "#finished?" do
    let(:purification_time) { build(:purification_time, remaining_time: remaining) }

    context "remaining_time が 0 のとき" do
      let(:remaining) { 0 }
      it { expect(purification_time.finished?).to be true }
    end

    context "remaining_time が 負の値のとき" do
      let(:remaining) { -10 }
      it { expect(purification_time.finished?).to be true }
    end

    context "remaining_time が 正の値のとき" do
      let(:remaining) { 600 }
      it { expect(purification_time.finished?).to be false }
    end
  end

  # =========================================================
  # #start!
  # =========================================================
  describe "#start!" do
    context "idle 状態のとき" do
      let(:purification_time) { create(:purification_time, :idle_with_time) }

      it "running 状態になること" do
        purification_time.start!
        expect(purification_time.reload).to be_running
      end

      it "started_at がセットされること" do
        freeze_time do
          purification_time.start!
          expect(purification_time.reload.started_at).to be_within(1.second).of(Time.current)
        end
      end

      it "total_time に remaining_time の値がセットされること" do
        purification_time.start!
        expect(purification_time.reload.total_time).to eq 600
      end
    end

    context "paused 状態のとき" do
      let(:purification_time) { create(:purification_time, :paused) }

      it "running 状態になること" do
        purification_time.start!
        expect(purification_time.reload).to be_running
      end

      it "total_time が再開時の remaining_time で更新されること" do
        purification_time.start!
        expect(purification_time.reload.total_time).to eq 300
      end
    end

    context "running 状態のとき" do
      let(:purification_time) { create(:purification_time, :running) }

      it "何も更新されないこと" do
        expect { purification_time.start! }.not_to change { purification_time.reload.updated_at }
      end
    end
  end

  # =========================================================
  # #stop!
  # =========================================================
  describe "#stop!" do
    context "running 状態で残り時間があるとき" do
      let(:purification_time) do
        create(:purification_time,
               status: :running,
               remaining_time: 600,
               total_time: 600,
               started_at: 3.minutes.ago)
      end

      it "paused 状態になること" do
        purification_time.stop!
        expect(purification_time.reload).to be_paused
      end

      it "remaining_time が経過分減ること" do
        purification_time.stop!
        # 600秒 - 180秒 = 420秒前後
        expect(purification_time.reload.remaining_time).to be_within(2).of(420)
      end

      it "paused_at がセットされること" do
        freeze_time do
          purification_time.stop!
          expect(purification_time.reload.paused_at).to be_within(1.second).of(Time.current)
        end
      end
    end

    context "running 状態で残り時間が 0 以下になっているとき" do
      let(:purification_time) do
        create(:purification_time,
               status: :running,
               remaining_time: 60,
               total_time: 60,
               started_at: 2.minutes.ago)
      end

      it "idle 状態に戻ること (finish!)" do
        purification_time.stop!
        expect(purification_time.reload).to be_idle
      end

      it "各値がリセットされること" do
        purification_time.stop!
        purification_time.reload
        aggregate_failures do
          expect(purification_time.remaining_time).to eq 0
          expect(purification_time.total_time).to eq 0
          expect(purification_time.started_at).to be_nil
          expect(purification_time.paused_at).to be_nil
        end
      end
    end

    context "idle 状態のとき" do
      let(:purification_time) { create(:purification_time) }

      it "何も更新されないこと" do
        expect { purification_time.stop! }.not_to change { purification_time.reload.updated_at }
      end
    end

    context "paused 状態のとき" do
      let(:purification_time) { create(:purification_time, :paused) }

      it "何も更新されないこと" do
        expect { purification_time.stop! }.not_to change { purification_time.reload.updated_at }
      end

      it "paused 状態のままであること" do
        purification_time.stop!
        expect(purification_time.reload).to be_paused
      end
    end
  end

  # =========================================================
  # #add_time
  # =========================================================
  describe "#add_time" do
    context "idle のとき" do
      let(:purification_time) { create(:purification_time, :idle_with_time) }

      it "remaining_time に加算され、状態は変わらないこと" do
        purification_time.add_time(300)

        aggregate_failures do
          expect(purification_time.remaining_time).to eq 900
          expect(purification_time.total_time).to eq 0
          expect(purification_time).to be_idle
        end
      end
    end

    context "paused のとき" do
      let(:purification_time) { create(:purification_time, :paused) }

      it "remaining_time に加算され、状態は変わらないこと" do
        purification_time.add_time(300)

        aggregate_failures do
          expect(purification_time.remaining_time).to eq 600
          expect(purification_time.total_time).to eq 600
          expect(purification_time).to be_paused
        end
      end

      it "付与後に再開して止めても付与分が残ること" do
        purification_time.add_time(300)
        purification_time.save!

        freeze_time do
          purification_time.start!
          travel 1.minute
          purification_time.stop!
        end

        # 300 + 300 - 60 = 540 秒
        expect(purification_time.reload.remaining_time).to eq 540
      end
    end

    context "保存について" do
      let(:purification_time) { create(:purification_time, :idle_with_time) }

      # 呼び出し側（PurificationTimeGranter）が台帳と一緒に 1 回で save! するため
      it "保存はしないこと" do
        purification_time.add_time(300)
        expect(purification_time.reload.remaining_time).to eq 600
      end
    end

    context "running かつ計測中のとき" do
      let!(:purification_time) { create(:purification_time, :running) }

      it "stop! したときに付与分が残り時間に反映されること" do
        travel_to(4.minutes.from_now) { purification_time.add_time(300) }
        purification_time.save!

        travel_to(6.minutes.from_now) { purification_time.stop! }

        # 600 + 300 - 360 = 540 秒
        expect(purification_time.reload.remaining_time).to be_within(2).of(540)
      end

      it "counting? の期限が付与分だけ延びること" do
        purification_time.add_time(300)

        aggregate_failures do
          travel_to(12.minutes.from_now) { expect(purification_time.counting?).to be true }
          travel_to(16.minutes.from_now) { expect(purification_time.counting?).to be false }
        end
      end

      # 画面表示（JS）は remaining_time - 経過秒、サーバーは total_time - 経過秒で計算するため
      it "remaining_time と total_time が等しいまま保たれること" do
        purification_time.add_time(300)
        expect(purification_time.remaining_time).to eq purification_time.total_time
      end

      # 修正前（#282）は running 中の付与が remaining_time にしか入らなかったため、
      # remaining_time > total_time のデータが残りうる。remaining_time 側が本来の残り
      it "修正前の付与で remaining_time が total_time より大きくても、remaining_time に揃えて延ばすこと" do
        purification_time.update!(remaining_time: 900)

        purification_time.add_time(300)

        aggregate_failures do
          expect(purification_time.remaining_time).to eq 1200
          expect(purification_time.total_time).to eq 1200
        end
      end
    end

    context "running のまま終了時刻を過ぎているとき" do
      let!(:purification_time) { create(:purification_time, :running) }

      it "精算されて idle になり、残り時間が付与分になること" do
        travel_to(60.minutes.from_now) { purification_time.add_time(600) }

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
          expect(purification_time.total_time).to eq 0
          expect(purification_time.started_at).to be_nil
        end
      end

      it "精算後もポモドーロをブロックしないこと（counting? が false）" do
        travel_to(60.minutes.from_now) do
          purification_time.add_time(600)
          expect(purification_time.counting?).to be false
        end
      end

      # travel_to は秒未満を切り捨てるため、factory の started_at（マイクロ秒付き）から
      # 期限を求めると期限のわずかに手前へ移動してしまう。秒ちょうどの started_at を置く
      it "ちょうど期限の瞬間に付与しても精算側に倒れること" do
        deadline = Time.zone.local(2026, 9, 9, 10, 10, 0)
        purification_time.update!(started_at: deadline - purification_time.total_time)

        travel_to(deadline) { purification_time.add_time(600) }

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
        end
      end

      # Granter を通すと、精算のあとで台帳を上書きするため、精算が台帳を消しても
      # 気づけない。台帳が消えると同じ 30 分を再付与できてしまうので、add_time を直接確かめる
      it "精算しても払い出し台帳は変わらないこと" do
        purification_time.update!(granted_blocks_date: Date.new(2026, 9, 9), granted_blocks_count: 2)

        travel_to(60.minutes.from_now) { purification_time.add_time(600) }

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.granted_blocks_date).to eq Date.new(2026, 9, 9)
          expect(purification_time.granted_blocks_count).to eq 2
        end
      end
    end

    context "running だが started_at が nil の不正データのとき" do
      let!(:purification_time) { create(:purification_time, :running, started_at: nil) }

      it "例外を出さず、精算されて残り時間が付与分になること" do
        purification_time.add_time(600)

        aggregate_failures do
          expect(purification_time).to be_idle
          expect(purification_time.remaining_time).to eq 600
        end
      end
    end
  end

  # =========================================================
  # #reset!
  # =========================================================
  describe "#reset!" do
    let(:purification_time) { create(:purification_time, :paused) }

    it "idle 状態に戻ること" do
      purification_time.reset!
      expect(purification_time.reload).to be_idle
    end

    it "各値が初期化されること" do
      purification_time.reset!
      purification_time.reload
      aggregate_failures do
        expect(purification_time.remaining_time).to eq 0
        expect(purification_time.total_time).to eq 0
        expect(purification_time.started_at).to be_nil
        expect(purification_time.paused_at).to be_nil
      end
    end
  end

  # =========================================================
  # #counting?
  # =========================================================
  describe "#counting?" do
    let!(:user) { create(:user) }

    context "idle のとき" do
      let!(:purification_time) { create(:purification_time, :idle_with_time, user: user) }

      it "false を返すこと" do
        expect(purification_time.counting?).to be false
      end
    end

    context "paused のとき" do
      let!(:purification_time) { create(:purification_time, :paused, user: user) }

      it "false を返すこと（残り時間を保持して止まっているだけで、計測はしていない）" do
        expect(purification_time.counting?).to be false
      end
    end

    context "running かつ終了時刻を過ぎていないとき" do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it "true を返すこと" do
        travel_to(5.minutes.from_now) do
          expect(purification_time.counting?).to be true
        end
      end
    end

    context "running のまま終了時刻を過ぎているとき" do
      let!(:purification_time) { create(:purification_time, :running, user: user) }

      it "false を返すこと（タブを閉じたまま時間切れになり stop! が呼ばれなかったケース。ここで true を返すと永久ロックになる）" do
        travel_to(11.minutes.from_now) do
          expect(purification_time.counting?).to be false
        end
      end
    end

    context "running だが started_at が nil のとき" do
      let!(:purification_time) { create(:purification_time, :running, user: user, started_at: nil) }

      it "false を返すこと（不正なデータで例外を出さない）" do
        expect(purification_time.counting?).to be false
      end
    end
  end

  # =========================================================
  # #granted_blocks_for
  # =========================================================
  describe "#granted_blocks_for" do
    let(:today) { Date.new(2026, 9, 9) }

    context "台帳の日付が問い合わせた日と一致するとき" do
      let(:purification_time) do
        build(:purification_time, granted_blocks_date: today, granted_blocks_count: 3)
      end

      it "保存されている払い出し数を返すこと" do
        expect(purification_time.granted_blocks_for(today)).to eq 3
      end
    end

    context "台帳の日付が前日のとき" do
      let(:purification_time) do
        build(:purification_time, granted_blocks_date: today - 1, granted_blocks_count: 3)
      end

      it "0 を返すこと（累計は 0 時にリセットされるため）" do
        expect(purification_time.granted_blocks_for(today)).to eq 0
      end
    end

    context "まだ一度も付与していないとき" do
      let(:purification_time) { build(:purification_time) }

      it "0 を返すこと" do
        expect(purification_time.granted_blocks_for(today)).to eq 0
      end
    end
  end

  # =========================================================
  # 台帳はタイマーの状態遷移で消えないこと
  # =========================================================
  describe "状態遷移と払い出し台帳" do
    let!(:purification_time) do
      create(:purification_time, :idle_with_time,
                                 granted_blocks_date: Date.current, granted_blocks_count: 2)
    end

    # 台帳が消えると、タイマーをリセットするだけで同じ 30 分を再度付与できてしまう
    it "reset! で払い出し台帳が消えないこと" do
      purification_time.reset!

      aggregate_failures do
        expect(purification_time.reload.remaining_time).to eq 0
        expect(purification_time.granted_blocks_for(Date.current)).to eq 2
      end
    end

    it "時間切れで終了しても払い出し台帳が消えないこと" do
      purification_time.start!

      travel_to(11.minutes.from_now) do
        purification_time.stop!
      end

      aggregate_failures do
        expect(purification_time.reload.remaining_time).to eq 0
        expect(purification_time.granted_blocks_for(Date.current)).to eq 2
      end
    end
  end
end

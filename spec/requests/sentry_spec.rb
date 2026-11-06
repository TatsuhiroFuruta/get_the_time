require "rails_helper"
require "sentry/test_helper"

# 本番の初期設定（config/initializers/sentry.rb）のまま、送信先だけをテスト用に差し替えて
# 「Sentry に実際に何が届くか」を確かめる。活動記録のコメントなどの私的な内容を
# 外部サービスへ送らないことが、このファイルの主な関心事である。
RSpec.describe "Sentry へのエラー送信", type: :request do
  include Sentry::TestHelper

  # setup_sentry_test はテスト環境を送信対象に加えた設定を残すので、他の spec のために戻す
  after(:all) { load Rails.root.join("config/initializers/sentry.rb") }

  describe "送信される内容" do
    let(:user) { create(:user) }
    let(:private_comment) { "誰にも見せたくない内容" }
    let(:event) { sentry_events.last.to_h }

    before do
      setup_sentry_test
      allow(ActivityRecordForm).to receive(:new).and_raise("テスト用の例外")
      allow_any_instance_of(StaticPagesController).to receive(:privacy).and_raise("テスト用の例外")
    end

    after { teardown_sentry_test }

    # show_exceptions が :rescuable なので、例外はテストまで伝わる。ここでは Sentry に
    # 届いた内容だけを見たいので握りつぶす。
    def post_activity_record
      post activity_records_path, params: { activity_record_form: { comment: private_comment } }
    rescue RuntimeError
      nil
    end

    def get_privacy_page
      get privacy_path
    rescue StandardError
      nil
    end

    context "ログイン中に例外が起きたとき" do
      before do
        sign_in user
        post_activity_record
      end

      it "例外が 1 件送られること" do
        expect(sentry_events.size).to eq(1)
      end

      it "ユーザー情報として ID だけが送られること" do
        expect(event[:user]).to eq(id: user.id)
      end

      it "リクエスト本文が送られないこと" do
        expect(event.to_json).not_to include(private_comment)
      end

      it "メールアドレスが送られないこと" do
        expect(event.to_json).not_to include(user.email)
      end

      it "IP アドレスが送られないこと" do
        expect(event.to_json).not_to include("127.0.0.1")
      end
    end

    context "検索語入りの URL を開いているときに例外が起きたとき" do
      let(:search_word) { "検索した私的な言葉" }
      let(:url_with_search_word) { "http://www.example.com/activity_records?#{{ q: { comment_cont: search_word } }.to_query}" }

      before do
        sign_in user
        begin
          get "#{privacy_path}?#{{ q: { comment_cont: search_word } }.to_query}",
              headers: {
                "Referer" => url_with_search_word,
                "Cookie" => "private_cookie=#{CGI.escape(search_word)}",
                "User-Agent" => "テスト用ブラウザ"
              }
        rescue RuntimeError
          nil
        end
      end

      it "例外が送られること" do
        expect(sentry_events.size).to eq(1)
      end

      it "クエリ文字列が送られないこと" do
        expect(event.dig(:request, :query_string)).to be_blank
      end

      it "Referer ヘッダーの値が送られないこと" do
        expect(event.dig(:request, :headers, "Referer")).to eq("[Filtered]")
      end

      it "Cookie の値が送られないこと" do
        aggregate_failures do
          expect(event.dig(:request, :cookies)).to be_blank
          expect(event.dig(:request, :headers, "Cookie")).to eq("[Filtered]")
        end
      end

      it "ブラウザの把握に使う User-Agent は送られること" do
        expect(event.dig(:request, :headers)).to include("User-Agent" => "テスト用ブラウザ")
      end

      it "検索語がどこにも含まれないこと" do
        payload = event.to_json

        aggregate_failures do
          expect(payload).not_to include(search_word)
          expect(payload).not_to include(CGI.escape(search_word))
        end
      end
    end

    # PostgreSQL のエラーメッセージ（DETAIL）には行の内容がそのまま入る。data_collection の
    # 設定では防げないので、本物の制約違反を起こして確かめる。
    context "データベースの制約違反が起きたとき" do
      let(:regret_record) { create(:regret_record, user: user, content: private_comment) }

      def violate_not_null
        regret_record.update_column(:user_id, nil)
      end

      before { sign_in user }

      it "行の内容が送られないこと" do
        allow_any_instance_of(StaticPagesController).to receive(:privacy) { violate_not_null }
        get_privacy_page

        aggregate_failures do
          expect(sentry_events.size).to eq(1)
          expect(event.to_json).not_to include(private_comment)
        end
      end

      it "例外のクラス名は送られること" do
        allow_any_instance_of(StaticPagesController).to receive(:privacy) { violate_not_null }
        get_privacy_page

        expect(event.dig(:exception, :values).map { |value| value[:type] }).to include("ActiveRecord::NotNullViolation")
      end

      it "別の例外に包まれていても、行の内容が送られないこと" do
        allow_any_instance_of(StaticPagesController).to receive(:privacy) do
          violate_not_null
        rescue ActiveRecord::StatementInvalid
          raise "画面の描画に失敗しました"
        end
        get_privacy_page

        expect(event.to_json).not_to include(private_comment)
      end

      it "重複登録で、他人のメールアドレスが送られないこと" do
        # スタックトレースにはこのファイルのコード行も入るので、アドレスをここに直接書かない
        other_user = create(:user)
        allow_any_instance_of(StaticPagesController).to receive(:privacy) do
          build(:user, email: other_user.email).save!(validate: false)
        end
        get_privacy_page

        aggregate_failures do
          expect(sentry_events.size).to eq(1)
          expect(event.to_json).not_to include(other_user.email)
        end
      end
    end

    # この例外のメッセージには IP アドレスが入る。発生するのは Rails::Rack::Logger の中で、
    # Sentry のミドルウェアより外側なので届かない。順序が変わったときに気づけるよう固定する。
    context "IP アドレスの偽装を検知したとき" do
      it "Sentry に何も送られないこと" do
        headers = { "X-Forwarded-For" => "203.0.113.10", "Forwarded" => "for=198.51.100.20" }

        aggregate_failures do
          expect { get privacy_path, headers: headers }.to raise_error(ActionDispatch::RemoteIp::IpSpoofAttackError)
          expect(sentry_events).to be_empty
        end
      end
    end

    # before_send には例外が渡されない（hint[:exception] が nil になる）。失敗すると
    # イベントが黙って捨てられ、画面にもエラーが出ないので気づきにくい。
    context "例外を伴わないメッセージを送ったとき" do
      it "メッセージがそのまま送られること" do
        Sentry.capture_message("テスト用の通知")

        aggregate_failures do
          expect(sentry_events.size).to eq(1)
          expect(event[:message]).to eq("テスト用の通知")
        end
      end
    end

    # 例外の種類を確かめられないイベントは、DB エラーの可能性があるので送らない
    context "元の例外を渡さずに、例外入りのイベントを送ったとき" do
      it "メッセージが送られないこと" do
        client = Sentry.get_current_client
        Sentry.capture_event(client.event_from_exception(RuntimeError.new(private_comment)))

        expect(sentry_events).to be_empty
      end
    end

    context "ログインしていないときに例外が起きたとき" do
      it "ユーザー情報が送られないこと" do
        get_privacy_page

        aggregate_failures do
          expect(sentry_events.size).to eq(1)
          expect(event[:user]).to be_blank
        end
      end
    end

    context "ログイン中の例外の後に、未ログインのリクエストで例外が起きたとき" do
      it "前のユーザーの ID が残らないこと" do
        sign_in user
        post_activity_record
        sign_out user
        get_privacy_page

        expect(event[:user]).to be_blank
      end
    end
  end

  describe "初期設定" do
    let(:configuration) { Sentry.configuration }

    # setup_sentry_test はテスト環境を送信対象に加えた設定を残すので、初期設定を読み直す
    before { load Rails.root.join("config/initializers/sentry.rb") }

    it "本番環境だけを送信対象にしていること" do
      expect(configuration.enabled_environments).to eq(%w[production])
    end

    it "SQL やログを記録しない設定であること" do
      expect(configuration.breadcrumbs_logger).to eq([])
    end

    it "ローカル変数を送らない設定であること" do
      expect(configuration.data_collection.stack_frame_variables.mode).to eq(:off)
    end

    it "SQL の値を送らない設定であること" do
      expect(configuration.data_collection.database_query_data).to be(false)
    end

    it "DSN を環境変数から読むこと" do
      dsn = "https://public@sentry.invalid/1"
      allow(ENV).to receive(:[]).and_call_original
      allow(ENV).to receive(:[]).with("SENTRY_DSN").and_return(dsn)
      load Rails.root.join("config/initializers/sentry.rb")

      expect(Sentry.configuration.dsn.to_s).to eq(dsn)
    end

    it "パフォーマンス計測を使わない設定であること" do
      expect(configuration.tracing_enabled?).to be(false)
    end
  end
end

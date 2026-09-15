# 使い終わったゲストユーザーとその関連データを削除するサービス。
#
# dependent: :destroy を使わず関連テーブルを一括 delete_all する。User#destroy は
# 関連を 1 行ずつ DELETE するため 1 ユーザーあたり約 74 クエリになり、ネットワーク
# 越しの Neon では往復回数がそのまま実行時間になる。一括削除なら件数によらず
# 8 クエリで済む。
#
# 削除対象テーブルの一覧をここにも持つことになるが、7 テーブルすべてに
# add_foreign_key が張られているため、User に関連を追加してここを更新し忘れれば
# User の DELETE が外部キー違反で失敗する。静かに孤児が残ることはない。
class GuestUserPurger
  # 無操作がこの時間を超えたゲストを削除対象にする。
  #
  # last_request_at は ApplicationController で 10 分間引きして更新するため、最大
  # 10 分古い値になりうる。したがって実際に削除されるのは「50〜60 分の無操作」で
  # あり、席を外した閲覧者を消してしまう事故が起きにくい。
  INACTIVE_FOR = 1.hour

  # 1 回の実行で削除する上限。想定外に溜まったときの実行時間を頭打ちにする。
  # 残りは次の訪問者が来たときに持ち越される。
  BATCH_SIZE = 500

  def self.call(except_id: nil)
    new(except_id: except_id).call
  end

  def initialize(except_id: nil)
    @except_id = except_id
  end

  # 削除した件数を返す。
  def call
    ids = target_ids
    return 0 if ids.empty?

    ActivityRecord.where(user_id: ids).delete_all
    RegretRecord.where(user_id: ids).delete_all
    RegretSummary.where(user_id: ids).delete_all
    PurificationTime.where(user_id: ids).delete_all
    LightTime.where(user_id: ids).delete_all
    DarkTime.where(user_id: ids).delete_all
    PomodoroSetting.where(user_id: ids).delete_all
    User.where(id: ids).delete_all
  end

  private

  attr_reader :except_id

  def target_ids
    scope = User.guest.where(last_request_at: ...INACTIVE_FOR.ago).limit(BATCH_SIZE)
    # except_id が nil のとき where.not(id: nil) は「id IS NOT NULL」になり意図が
    # 読めなくなるため、値があるときだけ条件を足す。
    scope = scope.where.not(id: except_id) if except_id

    scope.pluck(:id)
  end
end

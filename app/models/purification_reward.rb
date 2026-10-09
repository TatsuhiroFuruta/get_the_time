# 浄化タイマーの報酬（付与）のルールをまとめたクラス。テーブルは持たない。
#
# ブロックの粒度・抽選テーブル・ブロック数の計算・次の付与までの分数など、
# 活動記録の属性にも関連にも依存しない計算をここに置く。
class PurificationReward
  # 浄化タイマー付与の 1 ブロック（分）。この分数がたまるごとに抽選を 1 回引く。
  BLOCK_MINUTES = 30

  # 付与分数の重み付きテーブル（合計 100）
  TIME_TABLE = [
    { minutes: 8,  weight: 60 },
    { minutes: 10, weight: 30 },
    { minutes: 13, weight: 9  },
    { minutes: 15, weight: 1  }
  ].freeze

  # 1ブロック分の付与分数をランダム抽選
  def self.sample_minutes
    threshold = rand(100)
    cumulative = 0
    TIME_TABLE.each do |entry|
      cumulative += entry[:weight]
      return entry[:minutes] if threshold < cumulative
    end
    TIME_TABLE.last[:minutes]
  end

  # 累計分数から、消化済みのブロック数を求める。
  # 余りを翌日へ繰り越さない設計のため、付与済みブロック数は累計だけから導出できる。
  def self.blocks(minutes)
    [ minutes.to_i, 0 ].max / BLOCK_MINUTES
  end

  # blocks 回の抽選を引いた合計分数。乱数を含むため呼ぶたびに結果が変わる。
  def self.sample_minutes_for(blocks)
    return 0 if blocks <= 0

    blocks.times.sum { sample_minutes }
  end

  # 次の付与までの残り分数（マイページ表示用）。累計 0 分でも 30 を返す。
  #
  # 累計の余りではなく「払い出し済みブロック数の次の閾値」から逆算する。活動記録を
  # 削除すると累計だけが下がるため、余りだけを見ると実際より短い分数を表示してしまう。
  def self.minutes_until_next(total_minutes, granted_blocks = 0)
    next_threshold = (granted_blocks.to_i + 1) * BLOCK_MINUTES

    [ next_threshold - [ total_minutes.to_i, 0 ].max, 0 ].max
  end
end

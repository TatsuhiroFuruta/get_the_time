class PurificationTime < ApplicationRecord
  belongs_to :user

  enum :status, { idle: 0, running: 1, paused: 2, completed: 3 }
end

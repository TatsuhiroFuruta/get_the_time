require 'rails_helper'

RSpec.describe PurificationTime, type: :model do
  describe 'アソシエーション' do
    it 'User に属していること' do
      association = described_class.reflect_on_association(:user)
      expect(association.macro).to eq :belongs_to
    end
  end
end

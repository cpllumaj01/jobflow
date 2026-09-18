class Customer < ApplicationRecord
  belongs_to :user
  has_many :jobs, dependent: :destroy

  validates :name, presence: true
end

class Job < ApplicationRecord
  STATUSES = %w[draft quoted approved in_progress completed cancelled].freeze

  belongs_to :customer
  has_one :estimate, dependent: :destroy
  has_many :change_orders, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }
end

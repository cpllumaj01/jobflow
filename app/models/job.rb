class Job < ApplicationRecord
  STATUSES = %w[draft quoted approved in_progress completed cancelled].freeze

  belongs_to :customer
  has_one :estimate, dependent: :destroy
  has_many :change_orders, dependent: :destroy

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  def original_estimate_value
    estimate&.status == "approved" ? estimate.total : 0
  end

  def approved_change_order_total
    change_orders.where(status: "approved").includes(:change_order_line_items).sum(&:total)
  end

  def current_contract_value
    original_estimate_value + approved_change_order_total
  end
end

class Estimate < ApplicationRecord
  STATUSES = %w[draft sent approved rejected].freeze

  belongs_to :job
  has_many :estimate_line_items, dependent: :destroy

  accepts_nested_attributes_for :estimate_line_items, allow_destroy: true, reject_if: :all_blank

  validates :status, inclusion: { in: STATUSES }

  def total
    estimate_line_items.sum(&:line_total)
  end
end

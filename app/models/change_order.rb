class ChangeOrder < ApplicationRecord
  STATUSES = %w[draft pending approved rejected].freeze

  belongs_to :job
  has_many :change_order_line_items, dependent: :destroy

  accepts_nested_attributes_for :change_order_line_items, allow_destroy: true, reject_if: :all_blank

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  def total
    change_order_line_items.sum(&:line_total)
  end
end

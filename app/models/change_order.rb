class ChangeOrder < ApplicationRecord
  STATUSES = %w[draft pending approved rejected].freeze

  belongs_to :job
  has_many :change_order_line_items, dependent: :destroy

  accepts_nested_attributes_for :change_order_line_items, allow_destroy: true, reject_if: :all_blank

  validates :title, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_save :sync_approved_at

  def total
    change_order_line_items.sum(&:line_total)
  end

  private
    def sync_approved_at
      if status == "approved"
        self.approved_at = Time.current if will_save_change_to_status? || approved_at.nil?
      else
        self.approved_at = nil
      end
    end
end

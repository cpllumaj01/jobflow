class Estimate < ApplicationRecord
  STATUSES = %w[draft sent approved rejected].freeze

  belongs_to :job
  has_many :estimate_line_items, dependent: :destroy

  accepts_nested_attributes_for :estimate_line_items, allow_destroy: true, reject_if: :all_blank

  validates :status, inclusion: { in: STATUSES }

  before_save :sync_approved_at

  def total
    estimate_line_items.sum(&:line_total)
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

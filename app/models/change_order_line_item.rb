class ChangeOrderLineItem < ApplicationRecord
  belongs_to :change_order

  validates :description, presence: true
  validates :quantity, numericality: { greater_than: 0 }
  validates :unit_price, numericality: { greater_than_or_equal_to: 0 }

  def line_total
    quantity * unit_price
  end
end

class Activity < ApplicationRecord
  belongs_to :trackable, polymorphic: true
  belongs_to :actor, class_name: "User", optional: true, inverse_of: :activities

  validates :event, presence: true
  validate :metadata_is_an_object

  scope :newest_first, -> { order(created_at: :desc, id: :desc) }

  private
    def metadata_is_an_object
      errors.add(:metadata, "must be an object") unless metadata.is_a?(Hash)
    end
end

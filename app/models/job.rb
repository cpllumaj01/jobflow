class Job < ApplicationRecord
  STATUSES = %w[draft quoted approved in_progress completed cancelled].freeze

  belongs_to :customer
  has_one :estimate, dependent: :destroy
  has_many :change_orders, dependent: :destroy
  has_many :activities, as: :trackable, dependent: :destroy
  has_many_attached :files

  MAX_FILE_SIZE = 20.megabytes
  FILE_CONTENT_TYPES = {
    "pdf" => "application/pdf",
    "jpg" => "image/jpeg",
    "jpeg" => "image/jpeg",
    "png" => "image/png",
    "webp" => "image/webp",
    "txt" => "text/plain",
    "csv" => "text/csv",
    "docx" => "application/vnd.openxmlformats-officedocument.wordprocessingml.document",
    "xlsx" => "application/vnd.openxmlformats-officedocument.spreadsheetml.sheet"
  }.freeze
  validate :new_files

  validates :name, presence: true
  validates :status, inclusion: { in: STATUSES }

  before_save :sync_completed_at

  # Check the entire batch before Active Storage builds blobs or attachments.
  def valid_file_uploads?(uploads)
    uploads.each do |upload|
      next unless validate_file_size(upload.original_filename, upload.size)

      extension = File.extname(upload.original_filename).delete_prefix(".").downcase
      content_type = FILE_CONTENT_TYPES.key?(extension) ? detected_file_type(upload.tempfile, extension) : nil
      upload.content_type = content_type if validate_file_type(upload.original_filename, content_type)
    end
    errors.empty?
  end

  def original_estimate_value
    estimate&.status == "approved" ? estimate.total : 0
  end

  def approved_change_order_total
    if change_orders.loaded?
      change_orders.select { |change_order| change_order.status == "approved" }.sum(&:total)
    else
      change_orders.where(status: "approved").includes(:change_order_line_items).sum(&:total)
    end
  end

  def current_contract_value
    original_estimate_value + approved_change_order_total
  end

  private
    def sync_completed_at
      if status == "completed"
        self.completed_at = if will_save_change_to_status? || completed_at_in_database.nil?
          Time.current
        else
          completed_at_in_database
        end
      else
        self.completed_at = nil
      end
    end

    def new_files
      files.reject(&:persisted?).each do |file|
        validate_file_size(file.filename.to_s, file.blob.byte_size)
        validate_file_type(file.filename.to_s, file.blob.content_type)
      end
    end

    def validate_file_size(filename, byte_size)
      if byte_size > MAX_FILE_SIZE
        errors.add(:files, "\"#{filename}\" must be #{MAX_FILE_SIZE / 1.megabyte} MB or smaller per file")
        false
      elsif byte_size.zero?
        errors.add(:files, "\"#{filename}\" is empty; choose a file with content")
        false
      else
        true
      end
    end

    def validate_file_type(filename, content_type)
      extension = File.extname(filename).delete_prefix(".").downcase
      if content_type && FILE_CONTENT_TYPES[extension] == content_type
        true
      else
        errors.add(:files, "\"#{filename}\" has an unsupported format or its content does not match its extension")
        false
      end
    end

    def detected_file_type(io, extension)
      io.rewind
      # Omitting the name and declared MIME prevents filename-based fallback.
      content_type = Marcel::MimeType.for(io)
      if %w[txt csv].include?(extension) && %w[application/octet-stream text/plain text/csv].include?(content_type)
        io.rewind
        text = io.read.force_encoding(Encoding::UTF_8)
        FILE_CONTENT_TYPES[extension] if text.valid_encoding? && !text.match?(/[\x00-\x08\x0B\x0E-\x1F\x7F]/)
      else
        content_type
      end
    ensure
      io.rewind
    end
end

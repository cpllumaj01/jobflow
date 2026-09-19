json.extract! job, :id, :customer_id, :name, :description, :address, :status, :start_date, :estimated_completion_date, :completed_at, :created_at, :updated_at
json.url job_url(job, format: :json)

abort "Demo seeds are disabled in production." if Rails.env.production?

require Rails.root.join("lib/demo_data")

puts "Seeding JobFlow demo data..."
user = DemoData.populate!(password: "password")

puts
puts "Seed complete."
puts "Login:"
puts "  Email: demo@jobflow.test"
puts "  Password: password"
puts
puts "Created:"
puts "  #{user.customers.count} customers"
puts "  #{user.jobs.count} jobs"
puts "  #{user.jobs.joins(:estimate).count} estimates"
puts "  #{ChangeOrder.where(job_id: user.jobs.select(:id)).count} change orders"

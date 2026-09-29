puts "Seeding JobFlow demo data..."

user = User.find_or_initialize_by(email_address: "demo@jobflow.test")
user.password = "password"
user.password_confirmation = "password"
user.save!

# Only reset data owned by the demo account.
user.customers.destroy_all

# -------------------------------------------------------------------
# Customer 1: Johnson Residence
# -------------------------------------------------------------------

johnson = user.customers.create!(
  name: "Johnson Residence",
  contact_name: "Michael Johnson",
  email: "michael.johnson@example.com",
  phone: "203-555-0142",
  address: "48 Harbor View Drive, Fairfield, CT",
  notes: "Prefers text messages for scheduling updates."
)

kitchen = johnson.jobs.create!(
  name: "Kitchen Renovation",
  description: "Full kitchen renovation including cabinetry, countertops, lighting, and finish work.",
  address: "48 Harbor View Drive, Fairfield, CT",
  status: "in_progress",
  start_date: Date.current - 21.days,
  estimated_completion_date: Date.current + 24.days
)

kitchen_estimate = kitchen.create_estimate!(
  status: "approved",
  expires_on: Date.current + 30.days,
  notes: "Includes labor, materials, and standard installation."
)

kitchen_estimate.estimate_line_items.create!([
  {
    description: "Custom cabinetry",
    quantity: 1,
    unit_price: 12_000
  },
  {
    description: "Quartz countertops",
    quantity: 45,
    unit_price: 145
  },
  {
    description: "Installation labor",
    quantity: 80,
    unit_price: 85
  }
])

lighting_change = kitchen.change_orders.create!(
  title: "Under-cabinet lighting",
  description: "Add LED under-cabinet lighting and dimmer controls.",
  status: "approved",
  requested_at: Date.current - 10.days
)

lighting_change.change_order_line_items.create!([
  {
    description: "LED lighting kits",
    quantity: 4,
    unit_price: 95
  },
  {
    description: "Electrical labor",
    quantity: 3,
    unit_price: 85
  }
])

island_change = kitchen.change_orders.create!(
  title: "Larger kitchen island",
  description: "Increase island size and add additional electrical outlet.",
  status: "pending",
  requested_at: Date.current - 2.days
)

island_change.change_order_line_items.create!([
  {
    description: "Additional cabinetry and finish material",
    quantity: 1,
    unit_price: 1_450
  },
  {
    description: "Electrical outlet installation",
    quantity: 1,
    unit_price: 250
  }
])

# -------------------------------------------------------------------
# Customer 2: Rivera Residence
# -------------------------------------------------------------------

rivera = user.customers.create!(
  name: "Rivera Residence",
  contact_name: "Sofia Rivera",
  email: "sofia.rivera@example.com",
  phone: "203-555-0188",
  address: "122 Brookside Avenue, Westport, CT",
  notes: "Bathroom project planned before holiday travel."
)

bathroom = rivera.jobs.create!(
  name: "Primary Bathroom Remodel",
  description: "Replace shower, vanity, tile, fixtures, and lighting.",
  address: "122 Brookside Avenue, Westport, CT",
  status: "approved",
  start_date: Date.current + 14.days,
  estimated_completion_date: Date.current + 42.days
)

bathroom_estimate = bathroom.create_estimate!(
  status: "approved",
  expires_on: Date.current + 20.days,
  notes: "Fixture selections may affect final material cost."
)

bathroom_estimate.estimate_line_items.create!([
  {
    description: "Tile and waterproofing",
    quantity: 1,
    unit_price: 5_800
  },
  {
    description: "Vanity and fixtures",
    quantity: 1,
    unit_price: 4_250
  },
  {
    description: "Labor",
    quantity: 72,
    unit_price: 85
  }
])

# -------------------------------------------------------------------
# Customer 3: Harbor Dental Group
# -------------------------------------------------------------------

harbor_dental = user.customers.create!(
  name: "Harbor Dental Group",
  contact_name: "Dr. Emily Chen",
  email: "emily.chen@example.com",
  phone: "203-555-0127",
  address: "310 Commerce Drive, Stamford, CT",
  notes: "Commercial work must minimize disruption during business hours."
)

office = harbor_dental.jobs.create!(
  name: "Office Buildout",
  description: "Renovate reception area and construct two additional treatment rooms.",
  address: "310 Commerce Drive, Stamford, CT",
  status: "quoted",
  estimated_completion_date: Date.current + 90.days
)

office_estimate = office.create_estimate!(
  status: "sent",
  expires_on: Date.current + 14.days,
  notes: "Proposal pending customer approval."
)

office_estimate.estimate_line_items.create!([
  {
    description: "Framing and drywall",
    quantity: 1,
    unit_price: 14_500
  },
  {
    description: "Electrical work",
    quantity: 1,
    unit_price: 9_200
  },
  {
    description: "Finish carpentry",
    quantity: 1,
    unit_price: 7_800
  },
  {
    description: "Painting",
    quantity: 1,
    unit_price: 4_600
  }
])

# -------------------------------------------------------------------
# Customer 4: Thompson Residence
# -------------------------------------------------------------------

thompson = user.customers.create!(
  name: "Thompson Residence",
  contact_name: "James Thompson",
  email: "james.thompson@example.com",
  phone: "203-555-0199",
  address: "17 Maple Ridge Road, Trumbull, CT"
)

deck = thompson.jobs.create!(
  name: "Backyard Deck Replacement",
  description: "Remove existing deck and construct a new composite deck.",
  address: "17 Maple Ridge Road, Trumbull, CT",
  status: "draft"
)

deck_estimate = deck.create_estimate!(
  status: "draft",
  expires_on: Date.current + 30.days
)

deck_estimate.estimate_line_items.create!([
  {
    description: "Composite decking material",
    quantity: 1,
    unit_price: 8_400
  },
  {
    description: "Framing material",
    quantity: 1,
    unit_price: 3_100
  },
  {
    description: "Labor",
    quantity: 56,
    unit_price: 85
  }
])

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

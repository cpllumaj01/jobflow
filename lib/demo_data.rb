require "stringio"

module DemoData
  EMAIL = "demo@jobflow.test".freeze

  def self.populate!(password:)
    raise ArgumentError, "Demo password must be present." if password.blank?

    User.transaction do
      # Serialize refreshes, including concurrent first-time account creation.
      User.connection.execute("SELECT pg_advisory_xact_lock(74102, 1)")
      # All contacts and projects below are fictional demonstration data.
      user = User.find_or_initialize_by(email_address: EMAIL)
      user.password = password
      user.password_confirmation = password
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
        address: "17 Maple Ridge Road, Trumbull, CT",
        notes: "Planning the deck first; garage conversion deferred due to budget."
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

      # Additional kitchen changes demonstrate unapproved work without increasing
      # the current contract value.
      kitchen.change_orders.create!(
        title: "Pantry shelving upgrade",
        description: "Proposed adjustable oak shelves and pull-out storage for the pantry.",
        status: "draft",
        change_order_line_items_attributes: [
          { description: "Oak shelving", quantity: 6, unit_price: 125 },
          { description: "Installation labor", quantity: 4, unit_price: 85 }
        ]
      )

      kitchen.change_orders.create!(
        title: "Premium backsplash upgrade",
        description: "Handmade tile alternative declined; retain the original backsplash scope.",
        status: "rejected",
        requested_at: 14.days.ago,
        change_order_line_items_attributes: [
          { description: "Premium tile material allowance", quantity: 35, unit_price: 28 },
          { description: "Additional tile installation labor", quantity: 8, unit_price: 85 }
        ]
      )

      # Approval predates work; updating an already-approved record preserves these
      # historical dates through the existing approval timestamp callbacks.
      kitchen_estimate.update!(approved_at: 28.days.ago)
      lighting_change.update!(approved_at: 8.days.ago)
      bathroom_estimate.update!(approved_at: 7.days.ago)

      basement = rivera.jobs.create!(
        name: "Basement Finishing",
        description: "Finished a family room and home office with insulated walls, lighting, and durable flooring.",
        address: rivera.address,
        status: "completed",
        start_date: Date.current - 100.days,
        estimated_completion_date: Date.current - 35.days,
        completed_at: 38.days.ago
      )
      basement_estimate = basement.create_estimate!(
        status: "approved",
        expires_on: Date.current - 95.days,
        notes: "Completed within the approved scope; final walkthrough accepted.",
        estimate_line_items_attributes: [
          { description: "Framing, insulation, and drywall", quantity: 1, unit_price: 12_500 },
          { description: "Lighting and electrical installation", quantity: 1, unit_price: 4_800 },
          { description: "Luxury vinyl flooring", quantity: 650, unit_price: 8 },
          { description: "Trim and painting labor", quantity: 48, unit_price: 85 }
        ]
      )
      basement_estimate.update!(approved_at: 110.days.ago)

      garage = thompson.jobs.create!(
        name: "Garage Conversion",
        description: "Proposed conversion to a home studio cancelled before scheduling; customer retained the garage for parking.",
        address: thompson.address,
        status: "cancelled"
      )
      garage.create_estimate!(
        status: "rejected",
        expires_on: Date.current - 14.days,
        notes: "Proposal declined due to budget. No work was started.",
        estimate_line_items_attributes: [
          { description: "Insulation and interior walls", quantity: 1, unit_price: 9_600 },
          { description: "Windows and exterior door", quantity: 1, unit_price: 6_400 },
          { description: "Electrical and heating allowance", quantity: 1, unit_price: 7_500 }
        ]
      )

      kitchen.files.attach(
        io: StringIO.new(<<~SCOPE),
          Kitchen Renovation - Demo Project Scope

          Install custom cabinetry, quartz countertops, and finish carpentry.
          Approved addition: four under-cabinet LED lighting kits with dimmer controls.
          Larger island: pending approval. Pantry shelving: draft proposal.
          Premium backsplash: declined; retain the original scope.

          Fictional project document for the JobFlow demonstration account.
        SCOPE
        filename: "kitchen-renovation-scope.txt",
        content_type: "text/plain"
      )

      user
    end
  end
end

require Rails.root.join("lib/demo_data")

namespace :demo do
  desc "Replace only demo@jobflow.test data in production (requires opt-in and DEMO_PASSWORD)"
  task bootstrap: :environment do
    abort "Demo bootstrap is production-only." unless Rails.env.production?
    unless ENV["ALLOW_PRODUCTION_DEMO_BOOTSTRAP"] == "true"
      abort "Set ALLOW_PRODUCTION_DEMO_BOOTSTRAP=true to replace demo@jobflow.test data."
    end
    password = ENV["DEMO_PASSWORD"]
    unless password.present? && password.bytesize.between?(16, 72)
      abort "Supply DEMO_PASSWORD with 16–72 bytes via the runtime secret environment."
    end

    DemoData.populate!(password: password)
    puts "Demo bootstrap complete for #{DemoData::EMAIL}: 4 customers, 6 jobs, 6 estimates, 4 change orders, 1 attachment."
  end
end

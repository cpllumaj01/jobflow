class ApplicationMailer < ActionMailer::Base
  default from: Rails.env.production? ? ENV["MAILER_FROM"] : "from@example.com"
  layout "mailer"
end

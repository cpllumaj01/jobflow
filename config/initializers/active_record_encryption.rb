# Keep these stable and outside source control. Test databases use disposable keys.
%w[primary_key deterministic_key key_derivation_salt].each do |setting|
  name = "ACTIVE_RECORD_ENCRYPTION_#{setting.upcase}"
  value = ENV[name].presence
  value ||= SecureRandom.hex(32) if Rails.env.test?

  unless value || ENV["SECRET_KEY_BASE_DUMMY"].present?
    raise "#{name} is required for Active Record Encryption"
  end

  Rails.application.config.active_record.encryption.public_send("#{setting}=", value) if value
end

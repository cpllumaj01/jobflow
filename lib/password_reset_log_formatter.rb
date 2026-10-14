# Route parameters are filtered separately; Rails also logs raw paths and redirects.
class PasswordResetLogFormatter < Logger::Formatter
  def call(severity, time, progname, message)
    super(severity, time, progname, message.to_s.gsub(%r{(/passwords/)(?!new(?:[./\s?#"'<>]|\z))[^/\s?#"'<>]+}, '\1[FILTERED]'))
  end
end

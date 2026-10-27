# Rails skips rate limiting when a cache counter returns nil. Authentication
# must stop when the backing store cannot enforce the configured limit.
class AuthenticationRateLimitStore
  def initialize(store)
    @store = store
  end

  def increment(...)
    count = @store.increment(...)
    raise ActionController::TooManyRequests unless count.is_a?(Integer)

    count
  end
end

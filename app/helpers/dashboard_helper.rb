module DashboardHelper
  def dashboard_percentage(value, total)
    total.zero? ? 0 : (value.fdiv(total) * 100).round(2)
  end
end

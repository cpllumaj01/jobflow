module ApplicationHelper
  def status_badge_classes(status)
    colors = case status
    when "quoted", "sent"
      "bg-blue-50 text-blue-700 ring-blue-600/20"
    when "pending"
      "bg-amber-50 text-amber-800 ring-amber-600/20"
    when "in_progress"
      "bg-indigo-50 text-indigo-700 ring-indigo-600/20"
    when "approved", "completed"
      "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
    when "rejected", "cancelled"
      "bg-rose-50 text-rose-700 ring-rose-600/20"
    else
      "bg-slate-100 text-slate-700 ring-slate-600/20"
    end

    "inline-flex rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset #{colors}"
  end
end

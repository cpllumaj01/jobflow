module ApplicationHelper
  def status_badge_classes(status)
    colors = case status
    when "quoted"
      "bg-yellow-50 text-yellow-800 ring-yellow-600/20"
    when "sent"
      "bg-sky-50 text-sky-700 ring-sky-600/20"
    when "pending"
      "bg-amber-50 text-amber-800 ring-amber-600/20"
    when "in_progress"
      "bg-violet-50 text-violet-700 ring-violet-600/20"
    when "approved"
      "bg-blue-50 text-blue-700 ring-blue-600/20"
    when "completed"
      "bg-emerald-50 text-emerald-700 ring-emerald-600/20"
    when "rejected"
      "bg-rose-50 text-rose-700 ring-rose-600/20"
    when "cancelled"
      "bg-red-50 text-red-700 ring-red-600/20"
    else
      "bg-slate-100 text-slate-700 ring-slate-600/20"
    end

    "inline-flex rounded-full px-2.5 py-1 text-xs font-medium ring-1 ring-inset #{colors}"
  end
end

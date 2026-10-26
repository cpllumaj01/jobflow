module JobsHelper
  def activity_description(activity)
    case activity.event
    when "job_status_changed"
      "Job status changed"
    when "estimate_created"
      "Estimate ##{activity.metadata['estimate_id']} created"
    when "estimate_status_changed"
      "Estimate ##{activity.metadata['estimate_id']} marked as #{activity.metadata['new_status'].humanize.downcase}"
    when "change_order_created"
      "Change order created: #{activity.metadata['title']}"
    when "change_order_status_changed"
      "Change order marked as #{activity.metadata['new_status'].humanize.downcase}: #{activity.metadata['title']}"
    when "attachment_added"
      "Attachment added: #{activity.metadata['filename']}"
    when "attachment_removed"
      "Attachment removed: #{activity.metadata['filename']}"
    else
      activity.event.humanize
    end
  end
end

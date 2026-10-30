module ActivitiesHelper
  def activity_event_name(activity)
    activity.event.to_s.humanize.presence || "Activity recorded"
  end

  def activity_metadata(activity)
    return {} unless activity.metadata.is_a?(Hash)

    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(activity.metadata)
  end

  def activity_description(activity, metadata)
    if activity.event.to_s.end_with?("_status_changed") && metadata["new_status"].is_a?(String) && metadata["new_status"].present?
      subject = activity.event.delete_suffix("_status_changed").humanize
      new_status = metadata["new_status"].humanize
      previous_status = metadata["previous_status"]
      if previous_status.is_a?(String) && previous_status.present?
        "#{subject} changed from #{previous_status.humanize} to #{new_status}"
      else
        "#{subject} marked as #{new_status}"
      end
    else
      activity_event_name(activity)
    end
  end

  def activity_metadata_value(value, key = nil)
    if %w[completed_at previous_completed_at].include?(key) && value.is_a?(String)
      begin
        return activity_timestamp(Time.zone.iso8601(value))
      rescue ArgumentError
        # Preserve invalid values using the generic rendering below.
      end
    end
    if %w[previous_status new_status].include?(key) && value.is_a?(String) && value.present?
      return value.humanize
    end
    if key == "total" && value.to_s.match?(/\A-?\d+(\.\d+)?\z/)
      return number_to_currency(value)
    end
    if key == "line_item_count" && value.to_s.match?(/\A\d+\z/)
      return pluralize(value.to_i, "line item")
    end

    case value
    when true
      "Yes"
    when false
      "No"
    when Array, Hash
      JSON.pretty_generate(value)
    else
      value.to_s.presence || "—"
    end
  end

  def activity_timestamp(value)
    l(value.in_time_zone, format: "%b %-d, %Y at %-I:%M %p %Z")
  end
end

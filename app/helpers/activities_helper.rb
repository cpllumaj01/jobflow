module ActivitiesHelper
  def activity_event_name(activity)
    activity.event.to_s.humanize.presence || "Activity recorded"
  end

  def activity_metadata(activity)
    return {} unless activity.metadata.is_a?(Hash)

    ActiveSupport::ParameterFilter.new(Rails.application.config.filter_parameters).filter(activity.metadata)
  end

  def activity_metadata_value(value)
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
end

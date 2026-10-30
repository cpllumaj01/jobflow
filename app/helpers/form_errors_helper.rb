module FormErrorsHelper
  def field_error_attributes(form, field, error_attribute: field, describedby: nil)
    invalid = form.object.errors[error_attribute].any?
    descriptions = [ describedby, (form.field_id(field, :error) if invalid) ].compact.join(" ")

    { aria: { invalid: (true if invalid), describedby: descriptions.presence } }
  end

  def field_errors(form, field, error_attribute: field)
    messages = form.object.errors.full_messages_for(error_attribute).uniq
    return if messages.empty?

    tag.p safe_join(messages, tag.br), id: form.field_id(field, :error),
      class: "mt-2 text-sm text-red-700 [overflow-wrap:anywhere]"
  end
end

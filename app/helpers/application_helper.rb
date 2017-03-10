module ApplicationHelper


  def flash_class(level)
    case level.to_sym
      when :notice then
        'success'
      when :alert then
        'danger'
    end
  end


  def flash_message(type, text)
    flash[type] ||= []
    if flash[type].instance_of? String
      flash[type] = [flash[type]]
    end
    flash[type] << text
  end


  def render_flash_message(flash_value)
    if flash_value.instance_of? String
      flash_value
    else
      safe_join(flash_value, '<br/>'.html_safe)
    end
  end


  def translate_and_join(error_list)
    error_list.map { |e| I18n.t(e) }.join(', ')
  end


  # ActiveRecord::Assocations::CollectionAssociation is a proxy and won't
  # always load info. see the class documentation for more info
  def assocation_empty?(assoc)
    assoc.reload unless assoc.nil? || assoc.loaded?
    assoc.nil? ? true : assoc.size == 0
  end


  def i18n_time_ago_in_words(past_time)
    "#{t('time_ago', amount_of_time: time_ago_in_words(past_time))}"
  end


  # call field_or_default with the default value = an empty String
  def field_or_none(label, value, tag: :p, tag_options: {}, separator: ': ',
                    label_class: 'field-label', value_class: 'field-value')

    field_or_default(label, value, default: '', tag: tag, tag_options: tag_options, separator: separator,
                     label_class: label_class, value_class: value_class)
  end


  # Return the HTML for a simple field with "Label: Value"
  # If value is blank, return the value of default (default value for default = '')
  # Surround it with the given content tag (default = :p if none provided)
  # and use the tag options (if any provided).
  # Default class to surround the label and separator is 'field-label'
  # Default class to surround the value is 'field-value'
  #
  # Separate the Label and Value with the separator string (default = ': ')
  #
  #  Ex:  field_or_none('Name', 'Bob Ross')
  #     will produce:  "<p><span class='field-label'>Name: </span><span class='field-value'>Bob Ross</span></p>"
  #
  #  Ex:  field_or_default('Name', '', default: '(no name provided)')
  #     will produce:  "(no name provided)"
  #
  #  Ex:  field_or_default('Name', '', default: content_tag( :h4, '(no name provided)', class: 'empty-warning') )
  #     will produce:  "<h4 class='empty-warning'>(no name provided)</h4>"
  #
  # Ex: field_or_none('Name', 'Bob Ross', tag: :h2, separator: ' = ')
  #     will produce:  "<h2><span class='field-label'>Name = </span><span class='field-value'>Bob Ross</span></h2>"
  #
  # Ex: field_or_none('Name', 'Bob Ross', tag_options: {id: 'bob-ross'}, value_class: 'special-value')
  #     will produce:  "<p id='bob-ross'><span class='field-label'>Name: </span><span class='special-value'>Bob Ross</span></p>"
  #
  def field_or_default(label, value, default: '', tag: :p, tag_options: {}, separator: ': ',
                       label_class: 'field-label', value_class: 'field-value')


    if value.blank?
      ''
    else
      content_tag(tag, tag_options) do
        concat content_tag(:span, "#{label}#{separator}", class: label_class)
        concat content_tag(:span, value, class: value_class)
      end
    end

  end

end

class PromptTemplate
  VARIABLE_NAME = /[A-Za-z_][A-Za-z0-9_]*/
  PLACEHOLDER = /\{\{\s*(#{VARIABLE_NAME})\s*\}\}/

  attr_reader :template

  def initialize(template)
    @template = template.to_s
  end

  def variables
    template.scan(PLACEHOLDER).flatten.uniq
  end

  def render(values)
    template.gsub(PLACEHOLDER) { values.fetch(Regexp.last_match(1)) }
  end
end

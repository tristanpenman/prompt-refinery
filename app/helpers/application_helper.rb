module ApplicationHelper
  MARKDOWN_TAGS = %w[
    a blockquote br code del em h1 h2 h3 h4 h5 h6 hr li ol p pre
    strong table tbody td th thead tr ul
  ].freeze
  MARKDOWN_ATTRIBUTES = %w[href title].freeze

  def render_markdown(text)
    html = Commonmarker.to_html(
      text.to_s,
      options: { render: { unsafe: false } },
      plugins: { syntax_highlighter: nil }
    )

    sanitize(html, tags: MARKDOWN_TAGS, attributes: MARKDOWN_ATTRIBUTES)
  end
end

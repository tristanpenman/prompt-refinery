require "csv"

# Parses a CSV file into test suite variables and test case values. Each
# column becomes a variable, and each non-blank row becomes a test case.
class TestSuiteCsv
  class Error < StandardError; end

  Result = Data.define(:variables, :headers, :rows)

  MAX_BYTES = 5.megabytes
  MAX_COLUMNS = 50
  MAX_ROWS = 1_000
  VARIABLE_NAME = /\A#{PromptTemplate::VARIABLE_NAME}\z/

  def self.parse(input, header_row:)
    new(input, header_row: header_row).parse
  end

  def initialize(input, header_row:)
    @input = input
    @header_row = header_row
  end

  def parse
    records = read_records
    headers = @header_row ? records.shift&.first : nil
    width = headers ? headers.size : records.map { |cells, _line| cells.size }.max.to_i
    width -= 1 while width.positive? && blank_column?(headers, records, width - 1)
    headers = headers&.first(width)

    raise Error, "The CSV file has no columns" if width.zero?
    raise Error, "The CSV file has #{width} columns, but at most #{MAX_COLUMNS} are supported" if width > MAX_COLUMNS
    raise Error, "The CSV file has no test cases" if records.empty?
    raise Error, "The CSV file has #{records.size} test cases, but at most #{MAX_ROWS} are supported" if records.size > MAX_ROWS

    variables = variable_names(headers || Array.new(width))
    rows = records.map { |cells, line| row_values(variables, cells, line) }

    Result.new(variables: variables, headers: headers&.map(&:to_s), rows: rows)
  end

  private

  # Returns each non-blank row with the line it ends on, for error messages.
  def read_records
    csv = CSV.new(read_text)
    records = []
    csv.each do |cells|
      records << [ cells, csv.lineno ] unless cells.all? { |cell| cell.to_s.strip.empty? }
    end
    records
  rescue CSV::MalformedCSVError => error
    raise Error, "The CSV file could not be read: #{error.message}"
  end

  def read_text
    data = @input.respond_to?(:read) ? @input.read(MAX_BYTES + 1) : @input.to_s
    data = data.to_s
    raise Error, "The CSV file is larger than #{MAX_BYTES / 1.megabyte} MB" if data.bytesize > MAX_BYTES

    text = data.dup.force_encoding(Encoding::UTF_8).delete_prefix("﻿")
    raise Error, "The CSV file must be UTF-8 encoded" unless text.valid_encoding?

    text
  end

  # Spreadsheet exports often end rows with empty cells, which shouldn't become variables.
  def blank_column?(headers, records, index)
    headers.to_a[index].to_s.strip.empty? && records.all? { |cells, _line| cells[index].to_s.strip.empty? }
  end

  # Turns headers into unique variable names, keeping those that are already
  # valid and naming blank columns by their position.
  def variable_names(headers)
    used = Set.new
    headers.each_with_index.map do |header, index|
      name = header.to_s.strip
      unless name.match?(VARIABLE_NAME)
        name = ActiveSupport::Inflector.transliterate(name).gsub(/[^A-Za-z0-9_]+/, "_").gsub(/\A_+|_+\z/, "")
        name = "column_#{index + 1}" if name.empty?
        name = "_#{name}" if name.match?(/\A\d/)
      end

      unique_name(name, used).tap { |unique| used << unique }
    end
  end

  def unique_name(name, used)
    return name unless used.include?(name)

    suffix = 2
    suffix += 1 while used.include?("#{name}_#{suffix}")
    "#{name}_#{suffix}"
  end

  def row_values(variables, cells, line)
    extra = cells.drop(variables.size)
    if extra.any? { |cell| cell.to_s.strip.present? }
      raise Error, "Line #{line} has #{cells.size} values, but the CSV file only has #{variables.size} #{"column".pluralize(variables.size)}"
    end

    variables.each_with_index.to_h { |name, index| [ name, cells[index].to_s ] }
  end
end

# encoding: iso-8859-1
require 'csv'

class CSVLint
  attr_accessor :infile
  def initialize(input)
    @infile = input[:infile]
  end

  def to_csv
    idx = 0
    keys = nil
    IO.foreach(infile) do |line|
      $stderr.print "\r#{idx}"
      line = line.force_encoding('iso-8859-1')
      next if line['*** End of Data ***'] || line['Australian Company Names Index as at:']
      val = CSV.parse_line(line, col_sep: "\t", quote_char: "\x00").to_a
      if idx == 0
        keys = val
      else
        yield Hash[keys.zip(val)]
      end
      idx += 1
    end
  end
end

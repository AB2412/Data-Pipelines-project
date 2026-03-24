# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/au_companies_fetcher'

describe AuCompaniesFetcher do
  describe AuCompaniesFetcher::APIParser do
    context 'Prepare specs for investigation' do
      ['000003047', '000076648', '000076693', '000000680', '000077556', '616809486', '617683780'].each do |value|
        it 'should write to file' do
          response_write("from_source_#{value}.xml", Nokogiri::XML(AuCompaniesFetcher.fetch_datum(value)).to_xml)
          response_write("from_source_#{value}.json", JSON.pretty_generate(Hash.from_xml(AuCompaniesFetcher.fetch_datum(value))))
          response_write("#{value}.json", JSON.pretty_generate(AuCompaniesFetcher::APIParser.new(AuCompaniesFetcher.fetch_datum(value)).encapsulate_as_per_schema))
        end
      end
    end
  end
end

# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/us_la_companies_fetcher'

describe UsLaCompaniesFetcher do
  context 'comprehensive match' do
    context 'should match to expected value' do
      comprehensive_check do |uid|
        input_data = UsLaCompaniesFetcher.fetch_datum(uid)
        next if input_data.nil?
        processed_data = UsLaCompaniesFetcher.process_datum(input_data)
        next if processed_data.nil?
        if ENV['INPUT_WRITE_EXPECTED_VALUES']
          it '#fetch_datum should be able write dump files if required' do
            response_write("input_files/#{processed_data[:company_number]}.html", JSON.pretty_generate(input_data[:company_page]))
          end
        end

        it 'process_datum should validate against the JSON schema' do
          $stderr.puts 'Validating: ' + uid
          $stderr.puts UsLaCompaniesFetcher.validate_datum(processed_data.except(:data))
          expect(UsLaCompaniesFetcher.validate_datum(processed_data.except(:data))).to be_empty
        end

        it 'save_entity should persist to the sqlite' do
          expect(UsLaCompaniesFetcher.prepare_and_save_data(processed_data)).to be_empty
        end

        if ENV['OUTPUT_WRITE_EXPECTED_VALUES']
          it 'process_datum should be able write processed files' do
            response_write("output_files/#{uid}.json", JSON.pretty_generate(DeepSort.deep_sort(processed_data)))
          end
        end
      end
    end
  end
end

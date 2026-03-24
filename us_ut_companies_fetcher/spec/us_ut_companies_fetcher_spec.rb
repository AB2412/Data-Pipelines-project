# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/us_ut_companies_fetcher'

describe UsUtCompaniesFetcher do
  context 'comprehensive match' do
    context 'should match to expected value' do
      comprehensive_check do |uid|
        input_data = UsUtCompaniesFetcher.fetch_datum(uid)
        processed_data = UsUtCompaniesFetcher.process_datum(input_data)

        unless input_data.nil?
          it 'fetch_datum should produce valid headers' do
            expect(input_data.keys).to match_array([:company_page, :retrieved_at]) | match_array([:all_attributes, :company_number, :jurisdiction_code, :name, :retrieved_at])
          end
        end

        if ENV['INPUT_WRITE_EXPECTED_VALUES']
          it '#fetch_datum should be able write dump files if required' do
            response_write("input_files/#{uid}.html", input_data[:company_page])
          end
        end

        unless processed_data.nil?
          if ENV['OUTPUT_WRITE_EXPECTED_VALUES']
            it 'process_datum should be able write processed files' do
              response_write("output_files/#{uid}.json", (JSON.pretty_generate(DeepSort.deep_sort(processed_data))))
            end
          end

          it 'process_datum should validate against the JSON schema' do
            expect(UsUtCompaniesFetcher.validate_datum(processed_data.except(:data))).to be_empty
          end

          it 'save_entity should persist to the sqlite' do
            expect(UsUtCompaniesFetcher.prepare_and_save_data(processed_data)).to be_empty
          end
        end
      end
    end
  end

  context 'spot check' do
    it 'should match to expected value' do
      uid = spot_check
      datum = UsUtCompaniesFetcher.update_datum(uid)
      expect(datum.with_indifferent_access.keys).to match_array JSON.parse(dummy_response("output_files/#{uid}.json")).with_indifferent_access.keys
    end
  end
end

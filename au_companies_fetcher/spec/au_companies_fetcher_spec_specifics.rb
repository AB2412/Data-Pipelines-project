# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/au_companies_fetcher'

describe AuCompaniesFetcher do
  describe AuCompaniesFetcher::APIParser do
    # ['000003047', '000076648', '000076693', '000000680', '000077556']
    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_000003047.xml')).encapsulate_as_per_schema }
      context 'Investigate 000003047 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq("DARLING IS S'DORING/LIGHTERAGE CO LTD")
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Australian Public Company, Limited By Shares')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Externally Administered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to eq([{:uid=>"37000003047", :identifier_system_code=>"au_bn"}])
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(11)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(50)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_000076648.xml')).encapsulate_as_per_schema }
      context 'Investigate 000076648 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('WOODSON PTY LTD')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Australian Proprietary Company, Limited By Shares')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Registered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to eq([{:uid=>"79000076648", :identifier_system_code=>"au_bn"}])
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(13)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(23)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_000076693.xml')).encapsulate_as_per_schema }
      context 'Investigate 000076693 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('PORT JACKSON STEVEDORING PTY LTD')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Australian Proprietary Company, Limited By Shares')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Externally Administered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to be_nil
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(13)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(22)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_000000680.xml')).encapsulate_as_per_schema }
      context 'Investigate 000000680 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('TOWER INSURANCE LIMITED')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Foreign Company (Overseas)')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Deregistered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to eq([{:uid=>"51000000680", :identifier_system_code=>"au_bn"}])
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(8)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(50)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to eq('F')
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_000077556.xml')).encapsulate_as_per_schema }
      context 'Investigate 000077556 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('HILLSDALE INVESTMENTS PTY LTD')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Australian Proprietary Company, Limited By Shares')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Non-Active')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to be_nil
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(13)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(9)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_616809486.xml')).encapsulate_as_per_schema }
      context 'Investigate 000077556 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('BALU BLUE FOUNDATION INCORPORATED')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Registered Australian Body')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Registered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to eq([{:uid=>"69616809486", :identifier_system_code=>"au_bn"}])
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(10)
        end

        it 'should have valid filings' do
          expect(parser[:filings].size).to eq(2)
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end

        it 'should have valid registered_address' do
          expect(parser[:registered_address]).to eq({:country_code=>"AU", :locality=>"PORT LINCOLN", :postal_code=>"5606", :region=>"South Australia"})
        end
      end
    end

    describe 'Investigate individual company' do
      let(:parser) { AuCompaniesFetcher::APIParser.new(dummy_response('from_source_617683780.xml')).encapsulate_as_per_schema }
      context 'Investigate 000077556 case' do
        it 'should have valid name' do
          expect(parser[:name]).to eq('LOGISTICS PLUS PTY LTD')
        end

        it 'should have valid company_type' do
          expect(parser[:company_type]).to eq('Australian Proprietary Company, Limited By Shares')
        end

        it 'should have valid current_status' do
          expect(parser[:current_status]).to eq('Registered')
        end

        it 'should have valid identifier' do
          expect(parser[:identifiers]).to eq([{:uid=>"50617683780", :identifier_system_code=>"au_bn"}])
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes].size).to eq(12)
        end

        it 'should have valid all_attributes' do
          expect(parser[:all_attributes][:types_subclass_descr]).to eq('Proprietary Company')
        end

        it 'should have valid filings' do
          expect(parser[:filings]).to be_nil
        end

        it 'should have valid branch' do
          expect(parser[:branch]).to be_nil
        end

        it 'should have valid registered_address' do
          expect(parser[:registered_address]).to eq({:country_code=>"AU", :locality=>"LIGHTSVIEW", :postal_code=>"5085", :region=>"South Australia"})
        end

        it 'should have valid headquarters_address' do
          expect(parser[:headquarters_address]).to eq({:country_code=>"AU", :locality=>"LIGHTSVIEW", :postal_code=>"5085", :region=>"South Australia"})
        end
      end
    end
  end
end

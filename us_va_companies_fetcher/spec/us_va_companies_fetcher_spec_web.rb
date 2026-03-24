# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/us_va_companies_fetcher'

describe UsVaCompaniesFetcher do

  it "should extend with OpencBot methods" do
    UsVaCompaniesFetcher.should respond_to :save_data
  end

  describe "#parse_company_page" do
    describe "in general" do
      before do
        @company_page = dummy_response('company_page.html')
        @parse_company_page = UsVaCompaniesFetcher.parse_company_page(@company_page)
      end

      it "should return hash" do
        @parse_company_page.should be_kind_of Hash
      end

      describe "and company info hash" do
        it "should include name" do
          @parse_company_page[:name].should == "1 AAAA Aaron's Quality Traffic School, Inc."
        end

        it "should include company_type" do
          @parse_company_page[:company_type].should == 'Corporation'
        end

        it "should include registered_address" do
          @parse_company_page[:registered_address].should == "2685 LACYWOOD LANE, SANDSTON VA 23150"
        end

        it "should include current_status" do
          @parse_company_page[:current_status].should == 'Active'
        end

        it "should include incorporation_date" do
          @parse_company_page[:incorporation_date].should == '2000-06-23'
        end

        it "should include all_attributes" do
          @parse_company_page[:all_attributes][:registered_agent_name].should == 'DARRYL C GEORGE'
          @parse_company_page[:all_attributes][:registered_agent_address].should == '2685 LACYWOOD LANE, SANDSTON VA 23150'
          @parse_company_page[:all_attributes][:jurisdiction_of_origin].should == 'VA'
        end

      end
    end

  end

  describe "#parse_search_results_page" do
    before do
      @search_results_json = dummy_response('search_results.json')
      @search_results = UsVaCompaniesFetcher.parse_search_results_page(@search_results_json)
    end

    it "should return array of company_hashes" do
      @search_results.should be_kind_of Array
      @search_results.size.should == 18
      @search_results[0][:name].should == 'A'
      @search_results[0][:company_number].should == '03311958'
      @search_results[1][:company_number].should == 'S3021708'
      @search_results[1][:name].should == 'A-1-A L.L.C.'
      @search_results[1][:company_type].should == 'Limited Liability Company'
      @search_results[1][:current_status].should == 'Canceled'
    end

    it "should not include names" do
      @search_results.any?{ |r| r[:company_type][/name/i] }.should_not be true
    end

  end

  describe "convert_company_data" do
    before do
      @raw_data = {
        "rec_type"=>"02",
        "corp_id"=>"F000032",
        "corp_name"=>"AMERICAN BRANDS, INC.",
        "corp_status"=>"MERGED",
        "corp_status_date"=>"1986-06-30",
        "corp_per_dur"=>nil,
        "corp_inc_date"=>"1903-08-18",
        "corp_state_inc"=>"NJ",
        "corp_ind_code"=>"GENERAL",
        "corp_po_eff_date"=>nil,
        "corp_street1"=>"1701 1ST AVENUE",
        "corp_street2"=>nil,
        "corp_city"=>"ROCK ISLAND",
        "corp_state"=>"IL",
        "corp_zip"=>"61201",
        "corp_ra_name"=>"HENRY T. WICKHAM",
        "corp_ra_street1"=>"23RD FLOOR",
        "corp_ra_street2"=>"1111 EAST MAIN STREET",
        "corp_ra_city"=>"RICHMOND",
        "corp_ra_state"=>"VA",
        "corp_ra_zip"=>"23219",
        "corp_ra_eff_date"=>"1975-05-09",
        "corp_ra_status"=>"ATTORNEY",
        "corp_ra_loc"=>"216",
        "corp_stock_ind"=>"S",
        "corp_total_shares"=>"00260000000",
        "corp_asmt_ind"=>nil,
        "corp_stock_class"=>nil,
        "corp_stock_share_auth"=>nil,
        "corp_merger_ind"=>nil,
        "corp_stock_class_3"=>nil,
        "corp_stock_share_auth_3"=>nil,
        "corp_stock_class_4"=>nil,
        "corp_stock_share_auth_4"=>nil,
        "corp_stock_class_5"=>nil,
        "corp_stock_share_auth_5"=>nil,
        "corp_stock_class_6"=>nil,
        "corp_stock_share_auth_6"=>nil,
        "corp_stock_class_7"=>nil,
        "corp_stock_share_auth_7"=>nil}
    end

    it "should convert raw company data" do
      expected_result = {
        :company_number=>"F0000325", # check digit added
        :name=>"AMERICAN BRANDS, INC.",
        :current_status=>"MERGED",
        :branch => 'F',
        :incorporation_date=>"1903-08-18",
        :total_shares => {:number => 260000000},
        :registered_address => {:street_address => '1701 1ST AVENUE', :locality => 'ROCK ISLAND', :region => 'IL', :postal_code => '61201'},
        :all_attributes => {
          :registered_agent_name=>"HENRY T. WICKHAM",
          :jurisdiction_of_origin=>"NJ",
          :registered_agent_address => '23RD FLOOR, 1111 EAST MAIN STREET, RICHMOND, VA, 23219'
          }
        }
      UsVaCompaniesFetcher.convert_company_data(@raw_data).should == expected_result
    end
  end

  describe "calculate check digit" do
    UsVaCompaniesFetcher.calculate_check_digit('0492205').should == 0
    UsVaCompaniesFetcher.calculate_check_digit('0160397').should == 6
    UsVaCompaniesFetcher.calculate_check_digit('0160138').should == 4
    UsVaCompaniesFetcher.calculate_check_digit('F184068').should == 7
    UsVaCompaniesFetcher.calculate_check_digit('F159039').should == 9
    UsVaCompaniesFetcher.calculate_check_digit('S000014').should == 3
    UsVaCompaniesFetcher.calculate_check_digit('S079006').should == 5

  end
end

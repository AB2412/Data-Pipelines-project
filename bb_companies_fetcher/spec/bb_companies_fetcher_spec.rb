# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/bb_companies_fetcher'

describe BbCompaniesFetcher do

  it "should extend with OpencBot methods" do
    BbCompaniesFetcher.should respond_to :save_data
  end

  describe "#parse_company_page" do
    describe "in general" do
      before do
        @company_page = dummy_response('company_page1.html')
        @parse_company_page = BbCompaniesFetcher.parse_company_page(@company_page)
      end

      it "should return hash" do
        @parse_company_page.should be_kind_of Hash
      end

      describe "and company info hash" do
        it "should include name" do
          @parse_company_page[:name].should == "NCG INTERNATIONAL BUSINESS LTD."
        end

        it "should include company number" do
          @parse_company_page[:company_number].should == "31781"
        end

        it "should include incorporation_date" do
          @parse_company_page[:incorporation_date].should == '2009-03-25'
        end
      end
    end

    describe "in business names" do
      before do
        @company_page = dummy_response('company_page2.html')
        @parse_company_page = BbCompaniesFetcher.parse_company_page(@company_page)
      end

      it "should return string" do
        @parse_company_page.should be_kind_of String
      end
    end

    describe "in empty case" do
      before do
        @company_page = dummy_response('company_page3.html')
        @parse_company_page = BbCompaniesFetcher.parse_company_page(@company_page)
      end

      it "should return nil" do
        @parse_company_page.should be_nil
      end
    end
  end

end

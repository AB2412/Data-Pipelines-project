# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/il_companies_fetcher'

describe IlCompaniesFetcher do

  it "should extend with OpencBot methods" do
    IlCompaniesFetcher.should respond_to :save_data
  end

end

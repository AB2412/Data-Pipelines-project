# encoding: UTF-8
require_relative 'spec_helper'
require_relative '../lib/us_de_companies_fetcher'

describe UsDeCompaniesFetcher do

  it "should extend with OpencBot methods" do
    UsDeCompaniesFetcher.should respond_to :save_data
  end

end

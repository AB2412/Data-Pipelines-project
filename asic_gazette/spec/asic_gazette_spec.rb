require_relative 'spec_helper'
require_relative '../lib/asic_gazette'

describe AsicGazette do

  it "should extend with OpencExternalBot methods" do
    AsicGazette.should respond_to :save_data
  end

  describe '#parse_notice_page' do
    it "should extact data" do
      parsed_data = AsicGazette.parse_notice_page(dummy_response('winding_up_order.html'))
      parsed_data[:notice_data].should be_kind_of Hash
      parsed_data[:notice_data]['Company details'].should match(/application for the winding up/m)
    end
  end
 
  private
  def dummy_response(response_name)
    IO.read(File.join(File.dirname(__FILE__),"dummy_responses",response_name.to_s))
  end

end

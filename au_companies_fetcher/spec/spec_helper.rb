# encoding: UTF-8
require 'rspec'

# Utility method to allow sample html pages, csv files, json or whatever.
# Expects the files to be stored in a 'dummy_responses' folder in the spec directory
#
def dummy_response(response_name, options={})
  IO.read(File.join(File.dirname(__FILE__),"dummy_responses",response_name.to_s), options)
end

def response_write(file_name, response)
  IO.write(File.join(File.dirname(__FILE__),"dummy_responses",file_name.to_s), response)
end

def comprehensive_check
  IO.foreach('spec/check_ids.txt') do |uid|
    yield uid.strip
  end
end

def spot_check
  IO.readlines('spec/check_ids.txt').to_a.sample(1).first.strip
end

def tuple_to_schema(tuple)
  datum = tuple.delete_if{|k,v| k.class == Fixnum }.map do |k,v|
    if v.blank?
      Hash[k,nil]
    elsif v[/^\[|{/]
      Hash[k, JSON.parse(v)]
    else
      Hash[k,v]
    end
  end.inject(&:update).reject{|k,v| v.blank? }
  datum.sort.to_h
end

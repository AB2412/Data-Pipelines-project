class Array
  def strip
    collect{|a|a.strip}
  end
  def snap
    delete_if{|e| e.blank?}
  end
end
class Hash
  def snap
    delete_if{|k,v| [nil, [], {}, '', ',', '.', 'N/A', '9999-99-99'].include?( v ) }
  end
end

def normalise_date(str)
  return nil if str.blank?
  Date.parse(str).iso8601
end

def extract_names(str)
  str && str.scan(/(.*)\(USED\s{1,}IN\s{1,}VA\s{1,}BY:(.*)\)$/).flatten.strip
end

def clean_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
    address
  else
    tmp = address.values.join(', ').strip
    (tmp.size <= 3 ? nil : tmp)
  end
end

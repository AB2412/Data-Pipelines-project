INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,'].freeze
SOURCE_URL = 'https://enterprise.sos.nm.gov/api/businessEntitySearch/webSearch'
MAX_FAILED_COUNT = 30
FETCH_DATA_RUNTIME_LIMIT = 23 * 60 * 60

def clean_address(address)
  if address.key?(:street_address) || address.key?(:postal_code) || (address.key?(:locality) && address.key?(:country))
    address
  else
    tmp = address.values.snap.join(', ')
    (tmp.size <= 3 ? nil : tmp)
  end
end

class Hash
  def snap
    delete_if { |_k, v| INVALID_FIELDS.include?(v) }
  end
end

class Array
  def snap
    delete_if { |v| INVALID_FIELDS.include?(v) }
  end
end

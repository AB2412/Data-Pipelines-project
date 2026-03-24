INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,'].freeze

script_dir = File.dirname(File.expand_path(__FILE__))
company_type_file = File.join(script_dir, 'company_type.txt')
company_description_file = File.join(script_dir, 'description.txt')

def load_hash_from_file(file_path)
  hash = {}

  File.readlines(file_path).each do |line|
    key, value = line.chomp.split(':')
    hash[key.gsub('"', '').squish] = value.gsub('"', '').squish
  end

  hash
end

COMPANY_TYPE = load_hash_from_file(company_type_file)
DESCRIPTION = load_hash_from_file(company_description_file)

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

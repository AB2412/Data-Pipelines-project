INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,'].freeze
NARROW_SEARCH_RECORDS_LIMIT = 20000
PER_PAGE_RECORDS = 1000
FETCHING_RUNTIME_LIMIT = 36000

def read_json_file(file_name)
  JSON.parse(File.read("lib/mapping_files/#{file_name}"))
end

COMPANY_TYPE = read_json_file("company_type.json")
JURISDICTION_OF_ORIGIN = read_json_file("jurisdiction_of_origin.json")
REGION = read_json_file("region.json")

SEX_UNITE_LEGALE = {
  "F" => "MADAME",
  "M" => "MONSIEUR"
}

NUMBER_OF_EMPLOYEES = {
  'null' => '0',
  '00' => '0',
  '01' => '1-2',
  '02' => '3-5',
  '03' => '6-9',
  '11' => '10-19',
  '12' => '20-49',
  '21' => '50-99',
  '22' => '100-199',
  '31' => '200-249',
  '32' => '250-499',
  '41' => '500-999',
  '42' => '1000-1999',
  '51' => '2000-4999',
  '52' => '5000-9999',
  '53' => '10000-',
  'NN' => '0'
}

CATERGORY_ENTERPRISES = {
  "PME" => "PME - Petite ou Moyenne Entreprise",
  "ETI" => "ETI - Entreprise de Taille Intermédiaire",
  "GE" => "GE - Grande Entreprise"
}

JURISDICTION_CODE = {
  "971" => 'gp',
  "972" => 'mq',
  "973" => 'gf',
  "974" => 're',
  "976" => 'yt',
  "975" => 'pm',
  "977" => 'bl',
  "978" => 'mf',
  "986" => 'wf',
  "987" => 'pf',
  "988" => 'nc'
}

def clean_address(address)
  if (address.key?(:street_address) && (!address[:street_address].blank?)) || (address.key?(:postal_code) && !address[:postal_code].blank?) || ((address.key?(:locality) && !address[:locality].blank?) && (address.key?(:country) && !address[:country].blank?))
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

def working_data_folder
  folders = Dir.glob("#{data_dir}/*").select {|f| (File.directory? f) && (f.include? '_processing')}
  folders.first
end

def rename_working_data_folder
  wkfd = working_data_folder
  new_path = working_data_folder.gsub('_processing', '')
  if File.directory?(new_path)
    FileUtils.rm_rf(new_path)
  end
  File.rename(wkfd, new_path)
end

def clean_output_file(folder)
  File.open(folder, "w") do |f|
  end
end

def get_constant(const_name)
  get_var(const_name) || const_get(const_name)
end

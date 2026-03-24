INVALID_FIELDS = [nil, '', ' ', '. .', '-', {}, [], '00000', '0000', '.', ',,'].freeze
CODE_APE, ACTIVITY_DATA = [], []
FETCHING_RUNTIME_LIMIT = 36000
PAGE_SIZE_ARRAY = (20..700).to_a

CSV.foreach("lib/mapping_files/activity_file.csv", encoding: 'ISO-8859-1:UTF-8', headers: true) do |row|
  ACTIVITY_DATA << row.to_hash
end

def read_json_file(file_name)
  JSON.parse(File.read("lib/mapping_files/#{file_name}"))
end

CODE_APE = read_json_file("CODE_APE.json") unless Dir.glob("lib/mapping_files/*").map{|e| e.split("/").last}.exclude? "CODE_APE.json"
INPEE_COMPANY_TYPE = read_json_file("company_type.json")
COUNTRY_CODE = read_json_file("country_codes.json")
CURRENCIES = read_json_file("currency.json")
OFFICER_ROLES = read_json_file("officer_roles.json")
STREET_TYPE = read_json_file("street_type.json")

CURRENT_STATUS = {
  "1" => "Entreprise",
  "2" => "Etablissement"
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

GENDER = {
  "0" => "",
  "1" => "M",
  "2" => "F"
}

MARITAL_STATUS = {
  "1" => "Célibataire",
  "2" => "Divorcé",
  "3" => "Veuf",
  "4" => "Marié",
  "5" => "Pacsé",
  "6" => "En concubinage"
} 

TYPE_OFF = {
  "INDIVIDU" => "Personne Physique",
  "ENTREPRISE" => "Personne Morale",
  "ASSOCIATION" => "Association",
  "AUTRE" => "Autre"
}

ENTERPRISE = {
  "1" => "Siège",
  "2" => "Siège et établissement principal",
  "3" => "Établissement principal",
  "4" => "Établissement secondaire",
  "5" => "Premier établissement en France (d'une société étrangère)",
  "6" => "Firme étrangère employeur sans établissement en France",
  "11" => "Siège fermé",
  "12" => "Siège et établissement principal fermé",
  "13" => "Établissement principal fermé",
  "14" => "Établissement secondaire fermé",
  "15" => "Premier établissement en France (d'une société étrangère) fermé",
  "16" => "Firme étrangère employeur sans établissement en France fermé"
}

POUR_FORMALITY = {
  "1" => "Nouveau, ouverture",
  "2" => "Supprimé, fermeture",
  "3" => "Modifié",
  "4" => "Reprise d’activité après cessation temporaire",
  "5" => "Inchangé"
}

INSEE_DIFFUSION = {
  "O" => "Oui",
  "N" => "Non"
}

PERSONNE_TYPE = {
  "M" => "Personne Morale",
  "P" => "Personne Physique"
}

NATURE_GENRANCE = {
  "1" => "Majoritaire",
  "3" => "Minoritaire ou égalitaire, société associée",
  "4" => "Minoritaire ou égalitaire, sans société associée",
  "5" => "Gérance non associée, société associée",
  "6" => "Gérance non associée, sans société associée"
}

ACTIVITY_CODES = {
  "AGENT_COMMERCIAL" => "Agent commercial",
  "AGRICOLE_NON_ACTIF" => "Agricole : Périmètre des non actifs agricoles",
  "ACTIF_AGRICOLE" => "Agricole : Périmètre des actifs agricoles",
  "ARTISANALE" => "Artisanale non réglementée",
  "ARTISANALE_REGLEMENTEE" => "Artisanale réglementée",
  "COMMERCIALE" => "Commerciale",
  "INDEPENDANTE" => "Libérale non réglementée",
  "LIBERALE_REGLEMENTEE" => "Libérale réglementée",
  "LOUEUR_MEUBLE" => "Loueur meublé",
  "TOUTE_FORME_ACTIVITE" => "Toute forme d'activité",
  "GESTION_DE_BIENS" => "Gestion de biens",
  "LOUEUR_TERRE_AGRICOLE" => "Loueur terre agricole",
  "ACTIVITE_DE_PROSPECTION_UNIQUEMENT_NON_COMMERCIALE" => "Activité de prospection uniquement (non commerciale)",
  "SANS_ACTIVITE" => "Sans activité"
}

def clean_address(address)
  if (address.key?(:street_address) && (!address[:street_address].blank?)) || (address.key?(:postal_code) && !address[:postal_code].blank?) || ((address.key?(:locality) && !address[:locality].blank? ) && (address.key?(:country) && !address[:country].blank?))
    address
  elsif (!address[:country].blank?) && (address[:locality].blank?)
    nil
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

def clean_output_file(folder)
  File.open(folder, "w") do |f|
  end
end

def rename_working_data_folder
  wkfd = working_data_folder
  new_path = working_data_folder.gsub('_processing', '')
  File.rename(wkfd, new_path)
end

def clean_output_file(folder)
  File.open(folder, "w") do |f|
  end
end

def get_constant(const_name)
  get_var(const_name) || const_get(const_name)
end

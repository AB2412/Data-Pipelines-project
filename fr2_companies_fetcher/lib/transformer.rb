# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module Fr2CompaniesFetcher
  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    def run
      counter = 0
      start_time = Time.now.utc
      transformer_data = {}
      input_data do |json_data|
        entity_datum = encapsulate_as_per_schema(json_data)
        unless entity_datum.blank?
          validation_errors = validate_datum(entity_datum)
          raise "\n#{JSON.pretty_generate([entity_datum, validation_errors])}" unless validation_errors.blank?
          transformer_data[entity_datum[:company_number]] = entity_datum
          counter += 1
        end
      end

      transformer_data.values.each do |datum|
        persist(datum)
        save_entity(datum) unless ENV["NO_SAVE_DATA_IN_SQLITE"]
      end
      rename_working_data_folder
      res = { transformed: counter, transformer_start: start_time, transformer_end: Time.now.utc }
      res.merge!({ no_transformed_data: true }) if counter == 0
      res
    end


    class TransformerHelper
      def initialize(input)
        input.each do |key, value|
          self.class.__send__(:attr_accessor, key)
          __send__("#{key}=", value)
        end
      end

      def get_composition(composition, datum)
        composition.each do |composition_hash|
          officer_data = composition_hash.dig("individu", "descriptionPersonne")
          officer = {other_attributes: {address: {}}}

          process_officer_data(officer_data, officer, datum) if officer_data

          officer[:uid] = composition_hash["representantId"] if composition_hash["representantId"]
          officer[:position] = OFFICER_ROLES[composition_hash["roleEntreprise"]]
          officer[:other_attributes][:typeoff] = TYPE_OFF[composition_hash["typeDePersonne"]]
          officer[:other_attributes][:actif] = composition_hash["actif"]
          officer_address = composition_hash.dig("individu", "adresseDomicile")
          process_officer_address(officer_address, officer, datum) if officer_address
          clean_officer_data(officer)

          datum[:officers] << officer.snap
        end
        datum
      end

      def process_officer_data(officer_data, officer, datum)
        name = (officer_data["prenoms"].count < 2) ? "#{officer_data["nom"]} #{officer_data["prenoms"]&.first}".squish : "#{officer_data["nom"]} #{officer_data["prenoms"]&.first}, #{officer_data["prenoms"][1..]&.join(", ")}".squish rescue nil
        officer[:name] = name
        officer[:other_attributes][:date_of_birth] = officer_data["dateDeNaissance"]
        officer[:other_attributes][:nationality] = officer_data["nationalite"]
        officer[:other_attributes][:genre] = GENDER[officer_data["genre"]]
        officer[:other_attributes][:codeNationalite] = COUNTRY_CODE[officer_data["codeNationalite"]]
        officer[:other_attributes][:situationMatrimoniale] = MARITAL_STATUS[officer_data["situationMatrimoniale"]]
      end

      def process_officer_address(officer_address, officer, datum)
        address = officer[:other_attributes][:address]
        address[:country] = officer_address["pays"]
        address[:postal_code] = officer_address["codePostal"]
        address[:locality] = officer_address["commune"]
        address[:country_code] = COUNTRY_CODE[officer_address["codePays"]] rescue nil
        datum
      end

      def clean_officer_data(officer)
        officer[:other_attributes][:address] = clean_address(officer[:other_attributes][:address].snap)
        officer[:other_attributes].snap
      end

      def get_industry_codes(code)
        $stderr.puts "Code: #{code}"
        industry_hash = CODE_APE.select{|e| e["Code"].gsub(".",'') == code}.first
        industry_code_hash = {
          code: industry_hash["Code"], 
          description: industry_hash["Description"], 
          code_scheme_id: 'fr_naf_2008', 
          code_scheme_name: "Nomenclature d'activités française (2008)",
        } rescue nil
        industry_code_hash[:uid] = industry_code_hash[:code_scheme_id]+"-"+industry_code_hash[:code].gsub('.','') unless industry_code_hash.nil?
        industry_code_hash unless (industry_code_hash.nil?) || (industry_code_hash[:code].nil?)
      end

      def get_establishment_description(establishment_description, datum)
        datum[:all_attributes][:rolePourEntreprise] = ENTERPRISE[establishment_description["rolePourEntreprise"]]
        datum[:all_attributes][:headquarters_siret] = establishment_description["siret"]
        datum[:all_attributes][:statutPourFormalite] = POUR_FORMALITY[establishment_description["statutPourFormalite"]]
        datum[:all_attributes][:etablissementValidated] = establishment_description["etablissementValidated"]
        datum[:all_attributes][:etablissementRdd] = establishment_description["etablissementRdd"]
        datum
      end

      def get_headquarters_data(headquater_address, datum)
        datum[:headquarters_address] = get_address(headquater_address, datum[:headquarters_address])
        datum
      end

      def get_address(address, datum_address)
        datum_address[:country] = address["pays"] rescue nil
        datum_address[:country_code] = COUNTRY_CODE[address["codePays"]] rescue nil
        datum_address[:postal_code] = address["codePostal"]
        datum_address[:locality] = address["commune"]
        street_address = " #{address["numVoie"]} #{STREET_TYPE[address["typeVoie"]]} #{address["voie"]}"
        datum_address[:street_address] = street_address.squish rescue nil
        datum_address = clean_address(datum_address.snap)
        datum_address
      end

      def get_registered_address(address, datum)
        datum[:registered_address] = get_address(address, datum[:registered_address])
        datum[:all_attributes][:domiciliataire] = address["caracteristiques"]["domiciliataire"] rescue nil
        datum
      end

      def get_activities(activities, datum)
        activities.select{|e| e["indicateurPrincipal"] == true}.each do |activity_hash|
          activity = {}
          activity_data = ACTIVITY_DATA.select{|e| e["Code final"] == activity_hash["categoryCode"]}.first
          activity[:categoryCode] = activity_hash["categoryCode"]
          activity[:activiteId] = activity_hash["activiteId"]
          activity[:dateDebut] = activity_hash["dateDebut"]
          activity[:formeExercice] = activity_hash["formeExercice"]

          unless activity_data.nil?
            activity[:categorisationActivite1] = activity_data[activity_data.keys.select{|e| e.include? "Niv. 1"}[0]]
            activity[:categorisationActivite2] = activity_data[activity_data.keys.select{|e| e.include? "Niv. 2"}[0]]
            activity[:categorisationActivite3] = activity_data[activity_data.keys.select{|e| e.include? "Niv. 3"}[0]]
            activity[:categorisationActivite4] = activity_data[activity_data.keys.select{|e| e.include? "Niv. 4"}[0]]
          end

          activity[:descriptionDetaillee] = activity_hash["descriptionDetaillee"]
          activity[:indicateurArtisteAuteur] = activity_hash["indicateurArtisteAuteur"]
          activity[:indicateurMarinProfessionnel] = activity_hash["indicateurMarinProfessionnel"]
          activity[:rolePrincipalPourEntreprise] = activity_hash["rolePrincipalPourEntreprise"]

          activity[:activiteRattacheeEirl] = activity_hash["activiteRattacheeEirl"]
          datum[:all_attributes].merge!(activity)
        end
        datum
      end

      def get_description_data(description, datum)
        datum[:all_attributes][:objet] = description["objet"]
        datum[:all_attributes][:duree] = description["duree"]
        datum[:all_attributes][:dateClotureExerciceSocial] = description["dateClotureExerciceSocial"]
        datum[:all_attributes][:datePremiereCloture] = description["datePremiereCloture"]
        datum[:all_attributes][:ess] = description["ess"]
        datum[:all_attributes][:societeMission] = description["societeMission"]
        datum[:all_attributes][:capitalVariable] = description["capitalVariable"]
        datum[:all_attributes][:montantCapital] = description["montantCapital"]
        datum[:all_attributes][:deviseCapital] = CURRENCIES[description["deviseCapital"]]
        datum[:all_attributes][:indicateurOrigineFusionScission] = description["indicateurOrigineFusionScission"]
        datum[:all_attributes][:indicateurAssocieUnique] = description["indicateurAssocieUnique"]
        datum[:all_attributes][:depotDemandeAcre] = description["depotDemandeAcre"]
        datum[:all_attributes][:natureGerance] = NATURE_GENRANCE[description["natureGerance"]]
        datum[:all_attributes][:prorogationDuree] = description["prorogationDuree"]
        datum[:all_attributes][:continuationAvecActifNetInferieurMoitieCapital] = description["continuationAvecActifNetInferieurMoitieCapital"]
        datum
      end

      def get_identite_data(identite, datum, indicateur_associe_unique)
        enterprise = identite["entreprise"]
        datum[:name] = enterprise["denomination"]
        datum[:industry_codes] << get_industry_codes(enterprise["codeApe"])
        datum[:all_attributes][:nicSiege] = enterprise["nicSiege"]
        datum[:all_attributes][:entrepriseValidated] = enterprise["entrepriseValidated"]
        datum[:all_attributes][:entrepriseRdd] = enterprise["entrepriseRdd"]
        description = identite["description"]
        unless description.blank?
          datum = get_description_data(description, datum)
          datum[:all_attributes][:reconstitutionCapitauxPropres] = description["reconstitutionCapitauxPropres"]
        end
        publications = identite["publicationLegale"] rescue nil
        unless publications.nil?
          datum[:all_attributes][:typePublication] = publications["typePublication"]
          datum[:all_attributes][:datePublication] = publications["datePublication"]
          datum[:all_attributes][:journalPublication] = publications["journalPublication"]
          datum[:all_attributes][:publicationUrl] = publications["publicationUrl"]
        end
        datum
      end

      def get_structure_entreprise(structure_entreprise, datum)
        datum[:all_attributes][:dateAucuneActivite] = structure_entreprise["dateAucuneActivite"]
        datum[:all_attributes][:aucuneActivite] = structure_entreprise["aucuneActivite"]
        datum
      end

      def get_company_type(indicateur_associe_unique, forme_juridique_value)
        if (indicateur_associe_unique == true) && (forme_juridique_value.class == Array)
          company_type = forme_juridique_value.select{|e| e.include? "unique"}.first
          return (company_type.nil?) ? forme_juridique_value.select{|e| e.include? "unipersonnelle"}.first : company_type rescue nil
        elsif (indicateur_associe_unique == false) && (forme_juridique_value.class == Array)
          return forme_juridique_value.select{|e| e.exclude? "unique"}.first
        else
          return forme_juridique_value
        end
      end

      def get_dissolution_date(value)
        date_value = nil
        value.each do |key, val|
          case key
          when "natureCessationEntreprise"
            date_value = val["dateRadiation"] rescue nil
          when "exploitation"
            date_val = val["detailCessationEntreprise"]["dateRadiation"] rescue nil
            date_value = (date_val.nil?) ? val["detailCessationEntreprise"]["dateCessationTotaleActivite"] : date_val rescue nil
          when "personneMorale"
            date_dissolution_disparition = val["detailCessationEntreprise"]["dateDissolutionDisparition"] rescue nil
            date_mise_en_sommeil = val["detailCessationEntreprise"]["dateMiseEnSommeil"] rescue nil
            date_radiation = val["detailCessationEntreprise"]["dateRadiation"] rescue nil
            date_val = (date_dissolution_disparition.nil?) ? date_mise_en_sommeil : date_dissolution_disparition rescue nil
            date_value = (date_val.nil?) ? date_radiation : date_val
          when "personnePhysique"
            date_value = val["detailCessationEntreprise"]["dateRadiation"] rescue nil
          end
        end
        date_value
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: '',
          all_attributes: {},
          registered_address: {},
          filings: [],
          officers: [],
          identifiers: [],
          industry_codes: [],
          alternative_names: [],
          headquarters_address: {}
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when "INPI_DATA"
            object["company"].each do |outer_key, values|
              case outer_key
              when "siren"
                datum[:company_number] = values
                $stderr.puts "COMPANY_NUMBER: #{datum[:company_number]}"
              when "updatedAt"
                datum[:all_attributes][:source_updated_at] = values
              when "nombreRepresentantsActifs"
                datum[:all_attributes][:nombreRepresentantsActifs] = values
              when "nombreEtablissementsOuverts"
                datum[:all_attributes][:nombreEtablissementsOuverts] = values
              when "id"
                datum[:all_attributes][:source_id] = values
              when "formality"
                indicateur_associe_unique_value = values["content"]["personneMorale"]["identite"]["description"]["indicateurAssocieUnique"] rescue nil
                indicateur_associe_unique = (indicateur_associe_unique_value.nil?) ? false : indicateur_associe_unique_value
                values.each do |inner_key, value|
                  case inner_key
                  when "siren"
                  when "formeJuridique"
                  when "content"
                    return nil if (values["formeJuridique"] == "1000")
                    current_status = CURRENT_STATUS[value["natureCessation"]]
                    unless current_status.nil?
                      datum[:dissolution_date] = get_dissolution_date(value)
                    end

                    datum[:current_status] = ((current_status == "Entreprise") && !datum[:dissolution_date].blank?) ? "Cessée" : ((current_status == "Etablissement") && !datum[:dissolution_date].blank?) ? "Fermé" : "Actif" rescue nil
                    branch_value = value["succursaleOuFiliale"]
                    datum[:branch] = ((value["succursaleOuFiliale"] == "ETABLISSEMENT_OU_SUCCURSALE") || (value["succursaleOuFiliale"] == "BUREAU_DE_LIASON")) && (value["natureCreation"]["societeEtrangere"] == true) ? "F" : nil

                    datum[:all_attributes][:formeExerciceActivitePrincipale] = ACTIVITY_CODES[value["formeExerciceActivitePrincipale"]] rescue nil

                    if value["natureCreation"]
                      datum[:incorporation_date] = value["natureCreation"]["dateCreation"]
                      forme_juridique_value = INPEE_COMPANY_TYPE[value["natureCreation"]["formeJuridique"]]
                      datum[:company_type] = get_company_type(indicateur_associe_unique, forme_juridique_value)

                      datum[:all_attributes][:formeJuridiqueInsee] = value["natureCreation"]["formeJuridiqueInsee"]
                      datum[:all_attributes][:etablieEnFrance] = value["natureCreation"]["etablieEnFrance"] rescue nil
                      datum[:all_attributes][:salarieEnFrance]= value["natureCreation"]["salarieEnFrance"]
                      datum[:all_attributes][:relieeEntrepriseAgricole] = value["natureCreation"]["relieeEntrepriseAgricole"]
                      datum[:all_attributes][:entrepriseAgricole] = value["natureCreation"]["entrepriseAgricole"]
                    end
                    datum[:all_attributes][:domiciliataire] = value["personneMorale"]["adresseEntreprise"]["caracteristiques"]["domiciliataire"] rescue nil

                    address = value["personneMorale"]["adresseEntreprise"]["adresse"] rescue nil
                    unless address.nil?
                      commune_estab_code = address["codeInseeCommune"]
                      juris_code = JURISDICTION_CODE.find{|key, val| commune_estab_code.start_with?(key.to_s)}.first rescue nil
                      datum[:jurisdiction_code] = (juris_code.nil?) ? "fr" : JURISDICTION_CODE[juris_code]
                      datum = get_registered_address(address, datum)
                    end

                    establishment_description = value["personneMorale"]["etablissementPrincipal"]["descriptionEtablissement"] rescue nil
                    datum = get_establishment_description(establishment_description, datum) unless establishment_description.nil?


                    headquater_address = value["personneMorale"]["etablissementPrincipal"]["adresse"] rescue nil
                    datum = get_headquarters_data(headquater_address, datum) unless headquater_address.nil?

                    activities = value["personneMorale"]["etablissementPrincipal"]["activites"] rescue nil
                    datum = get_activities(activities, datum) unless activities.nil?

                    autresEstablishment = value["personneMorale"]["autresEtablissements"] rescue nil #need to ask how to store it its an array

                    composition = value["personneMorale"]["composition"]["pouvoirs"] rescue nil
                    datum = get_composition(composition, datum) unless composition.nil?

                    identite = value["personneMorale"]["identite"] rescue nil
                    datum = get_identite_data(identite, datum, indicateur_associe_unique) unless identite.nil?

                    structure_entreprise = value["personneMorale"]["structureEntreprise"] rescue nil
                    datum = get_structure_entreprise(structure_entreprise, datum) unless structure_entreprise.nil?
                  when "historique"
                  when "diffusionINSEE"
                    datum[:all_attributes][:diffusionINSEE] = INSEE_DIFFUSION[value]
                  when "diffusionCommerciale"
                    datum[:all_attributes][:diffusionCommerciale] = value
                  when "typePersonne"
                    return nil if value == "P"
                    datum[:all_attributes][:typePersonne] = PERSONNE_TYPE[value]
                  when "created"
                    datum[:all_attributes][:created] = value
                  when "updated"
                    datum[:all_attributes][:updated] = value
                  end
                end
              end
            end
          when "RetrievedAt"
            datum[:retrieved_at] = object
          end
        end
        return nil if datum.blank?
        datum[:jurisdiction_code] = "fr" if datum[:jurisdiction_code].blank?
        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }
        datum[:officers].snap
        datum[:all_attributes].snap
        datum[:identifiers].snap
        datum[:industry_codes].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?
        datum.snap
        datum[:dissolution_date] = "" if datum[:dissolution_date].blank?
        datum[:registry_url] = "https://data.inpi.fr/entreprises/#{datum[:company_number]}"
        datum
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end

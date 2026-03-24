# frozen_string_literal: true

require 'openc_bot/helpers/pseudo_machine_transformer'

module FrCompaniesFetcher
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

      def get_parse_date(date_value)
        Date.strptime(date_value, "%Y-%m-%d") rescue nil
      end

      def get_name(value, obj)
        sex_unite = SEX_UNITE_LEGALE[value]
        name = "#{sex_unite} #{obj["prenom1UniteLegale"]} #{obj["prenom2UniteLegale"]} #{obj["prenom3UniteLegale"]} #{obj["prenom4UniteLegale"]}"
        name.squish
      end

      def get_identifier_hash(value)
        {uid: value, identifier_system_code: "fr_rna"}
      end

      def get_company_type(obj)
        obj["periodesUniteLegale"].first["categorieJuridiqueUniteLegale"]
      end

      def alternative_names_append(datum, data_hash)
        datum << data_hash unless (data_hash.values.any?(&:blank?))
        datum
      end

      def get_retrieved_at(value, retrive_date)
        datum_date = Time.parse(retrive_date)
        other_retrieve_at = Time.parse(value)
        (other_retrieve_at > datum_date) ? value : retrive_date
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
          alternative_names: []
        }
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          warn "********** legend: #{legend} ***************"
          case legend
          when "SIREN_DATA"
            object.each do |key, value|
              case key
              when "siren"
                datum[:company_number] = value
                warn "COMPANY NUMBER: #{datum[:company_number]}"
              when "statutDiffusionUniteLegale"
                datum[:all_attributes][:restricted_for_marketing] = false
              when "dateCreationUniteLegale"
                datum[:incorporation_date] = get_parse_date(value)
              when "sexeUniteLegale"
                datum[:name] = get_name(value, object)
              when "sigleUniteLegale"
                datum[:alternative_names] = alternative_names_append(datum[:alternative_names], {company_name: value, type: "abbreviation"})
              when "prenomUsuelUniteLegale"
              when "pseudonymeUniteLegale"
              when "identifiantAssociationUniteLegale"
                datum[:identifiers] << get_identifier_hash(value) unless value.blank?
              when "trancheEffectifsUniteLegale"
                datum[:all_attributes][:number_of_employees] = NUMBER_OF_EMPLOYEES[value]
              when "anneeEffectifsUniteLegale"
              when "dateDernierTraitementUniteLegale"
              when "nombrePeriodesUniteLegale"
              when "categorieEntreprise"
                datum[:all_attributes][:company_size] = CATERGORY_ENTERPRISES[value] unless value.nil?
              when "anneeCategorieEntreprise"
              when "periodesUniteLegale"
                historical_data = value.first
                historical_data.each do |key, values|
                  case key
                  when "etatAdministratifUniteLegale"
                    datum[:current_status] = values
                  when "dateDebut"
                    datum[:dissolution_date] = get_parse_date(values)
                  when "denominationUniteLegale"
                    datum[:name] = values if datum[:name].blank?
                  when "categorieJuridiqueUniteLegale"
                    datum[:company_type] = COMPANY_TYPE[values]
                  when "nomUniteLegale"
                    nom_usage_unite_val = historical_data["nomUsageUniteLegale"]
                    unless (nom_usage_unite_val.nil?) || (values.nil?)
                      datum[:name] = datum[:name] + " " + nom_usage_unite_val
                    else
                      datum[:name] = datum[:name] + " " + values unless values.nil?
                    end
                    datum[:name] = datum[:name].squish
                  when "denominationUsuelle1UniteLegale", "denominationUsuelle2UniteLegale", "denominationUsuelle3UniteLegale"
                    datum[:alternative_names] = alternative_names_append(datum[:alternative_names], {company_name: values, type: "trading"})
                  when "nomenclatureActivitePrincipaleUniteLegale"
                    @industry_code_value = value
                  when "activitePrincipaleUniteLegale"
                    if historical_data["nomenclatureActivitePrincipaleUniteLegale"] == "NAFRev2"
                      industry_code_hash = {
                        code: values,
                        description: NAF_HASH[values],
                        code_scheme_id: 'fr_naf_2008',
                        code_scheme_name: "Nomenclature d'activités française (2008)",
                      }
                      industry_code_hash[:uid] = industry_code_hash[:code_scheme_id]+"-"+industry_code_hash[:code].gsub('.','') rescue nil
                      datum[:industry_codes] << industry_code_hash unless (NAF_HASH[values].nil?)
                    end
                  when "nicSiegeUniteLegale"
                    datum[:all_attributes][:headquarters_nic] = values
                  when "economieSocialeSolidaireUniteLegale"
                    datum[:all_attributes][:social_solidarity_economy] = values
                  end
                end
              end
            end
          when "SIRET_DATA"
            object.each do |key, value|
              case key
              when "siret"
                datum[:all_attributes][:headquarters_siret] = value
              when "statutDiffusionEtablissement"
              when "dateDernierTraitementEtablissement"
                datum[:retrieved_at] = value
              when "uniteLegale"
                datum[:retrieved_at] = get_retrieved_at(value["dateDernierTraitementUniteLegale"], datum[:retrieved_at])
                #Added for current_status if the current status is nil in siren data
                datum[:current_status] = (datum[:current_status].nil?) ? value["etatAdministratifUniteLegale"] : datum[:current_status]
                if (datum[:current_status] == "A")
                  if value["etatAdministratifEtablissement"] == "F"
                    datum[:current_status] = "Fermé"
                  else
                    datum[:current_status] = "Actif"
                    datum[:dissolution_date] = ""
                  end
                elsif (datum[:current_status] == "C") && (!datum[:dissolution_date].nil?)
                  datum[:current_status] = "Cessée"
                elsif (datum[:current_status] == "C") && (datum[:dissolution_date].nil?)
                   datum[:current_status] = "Actif"
                else
                  raise "Invalid etatAdministratifUniteLegale: #{datum[:current_status]}"      
                end
              when "adresseEtablissement"
                commune_estab_code = value["codeCommuneEtablissement"]
                street_address = "#{value["complementAdresseEtablissement"]} #{value["numeroVoieEtablissement"]} #{value["typeVoieEtablissement"]} #{value["libelleVoieEtablissement"]} #{value["distributionSpecialeEtablissement"]}"
                datum[:registered_address][:street_address] = street_address.squish
                juris_code = JURISDICTION_CODE.find{|key, val| commune_estab_code.start_with?(key.to_s)}.first rescue nil
                datum[:jurisdiction_code] = (juris_code.nil?) ? "fr" : JURISDICTION_CODE[juris_code]
                datum[:all_attributes][:jurisdiction_of_origin] = JURISDICTION_OF_ORIGIN[value["codePaysEtrangerEtablissement"]]&.downcase

                datum[:registered_address][:postal_code] = value["codePostalEtablissement"]
                region_code = (datum[:jurisdiction_code] == "fr") ? (datum[:registered_address][:postal_code][0..1]) : (datum[:registered_address][:postal_code][0..2]) rescue nil

                unless commune_estab_code.nil?
                  if (commune_estab_code.start_with?("2A")) && (region_code == "20")
                    datum[:registered_address][:region] = "CORSE-DU-SUD"
                  elsif (commune_estab_code.start_with?("2B")) && (region_code == "20")
                    datum[:registered_address][:region] = "HAUTE-CORSE"
                  else
                    datum[:registered_address][:region] = REGION[region_code]
                  end
                end

                datum[:branch] = "F" unless (datum[:all_attributes][:jurisdiction_of_origin].nil?) || (value["libellePaysEtrangerEtablissement"].nil?)

                if datum[:branch].nil?
                  datum[:registered_address][:country] = (value["codePaysEtrangerEtablissement"].nil?) && (value["libellePaysEtrangerEtablissement"].nil?) ? "FRANCE" : value["libellePaysEtrangerEtablissement"]
                  datum[:registered_address][:locality] = value["libelleCommuneEtablissement"]
                else
                  datum[:registered_address][:country] = (value["codePaysEtrangerEtablissement"].nil?) && (value["libellePaysEtrangerEtablissement"].nil?) ? "FRANCE" : value["libellePaysEtrangerEtablissement"]
                  datum[:registered_address][:locality] = value["libelleCommuneEtrangerEtablissement"]
                end
              when "enseigne1Etablissement", "enseigne2Etablissement", "enseigne3Etablissement"
                datum[:alternative_names] = alternative_names_append(datum[:alternative_names], {company_name: value, type: "trading"})
              when "periodesEtablissement"
                value.first.each do |key, values|
                  case key
                  when "denominationUsuelleEtablissement"
                    datum[:alternative_names] = alternative_names_append(datum[:alternative_names], {company_name: values, type: "trading"})
                  when 'nomenclatureActivitePrincipaleEtablissement'

                  end
                end
              when "activitePrincipaleEtablissement"
              end
            end
          when "RetrievedAt"
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        return nil if datum.blank?
        datum[:officers]&.delete_if { |officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/] }
        datum[:all_attributes].snap
        datum[:identifiers].snap
        datum[:registered_address] = clean_address(datum[:registered_address])
        datum[:registered_address].snap unless (datum[:registered_address].class == String) || (datum[:registered_address].nil?)
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?
        datum.snap
        datum[:dissolution_date] = "" if datum[:dissolution_date].nil?
        datum[:registry_url] = "https://annuaire-entreprises.data.gouv.fr/entreprise/#{datum[:company_number]}"
        datum
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end

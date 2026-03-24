require 'openc_bot/helpers/pseudo_machine_transformer'
require 'byebug'
module UsFrCompaniesFetcher

  module Transformer
    extend OpencBot::Helpers::PseudoMachineTransformer

    module_function

    def encapsulate_as_per_schema(payload)
      TransformerHelper.new(input: payload).encapsulate_as_per_schema
    end

    class TransformerHelper
      include OpencBot::Helpers::RegisterMethods
      def initialize(input)
        input.each do |key, value|
          self.class.__send__(:attr_accessor, key)
          __send__("#{key}=", value)
        end
      end

      def process_address(address_object)
        if ![address_object["numVoie"], address_object["typeVoie"], address_object["voie"]].compact.join(" ").present? ||
           !address_object["codePostal"].present? ||
           !(address_object["commune"].present? && address_object["pays"].present?)
          return {}
        else
          return {
            country: address_object["pays"],
            postal_code: address_object["codePostal"],
            locality: address_object["commune"],
            street_address: [address_object["numVoie"], address_object["typeVoie"], address_object["voie"]].compact.join(" ")
          }
        end
      end

      def encapsulate_as_per_schema
        datum = {
          jurisdiction_code: 'fr',
          all_attributes: {},
          company: {},
          alternative_names: [],
          industry_codes: [],
          officers: [],
          total_shares: {},
          filings: []
        }
        officer_hash = {other_attributes: {}}
        enterprise_officer_hash = {other_attributes: {}}
        industry_code = {}
        controlling_entities_name = []
        IO.write('tmp/parsed.json', JSON.pretty_generate(input))
        input.snap.each do |legend, object|
          case legend
          when 'RetrievedAt'
            datum[:retrieved_at] = object
            datum[:all_attributes][:source_created_at] = object
          when 'id'
            datum[:all_attributes][:source_id] = object
          when 'formality'
            object.each do |formality_legend, formality_object|
              case formality_legend
              when 'siren'
              when 'content'
                formality_object.each do |content_legend, content_object|
                  case content_legend
                  when 'formeExerciceActivitePrincipale'
                    datum[:all_attributes][:main_activity] = content_object
                  when 'natureCreation'
                    content_object.each do |nature_legend, nature_object|
                      case nature_legend
                      when 'dateCreation'
                        datum[:incorporation_date] = nature_object
                      when 'societeEtrangere'
                        datum[:branch] = (nature_object) ? 'F' : nil
                      when 'etablieEnFrance'
                        if (nature_object)
                          all_attribute = {"Citienship" => "Domestic"}
                          datum[:all_attributes] = all_attribute
                        end
                      when 'salarieEnFrance'
                      when 'formeJuridique'
                      when 'microEntreprise'
                      when 'relieeEntrepriseAgricole'
                      when 'entrepriseAgricole'
                      when 'eirl'
                      else
                        raise "Unhandled nature legend: #{nature_legend}"
                      end
                    end
                  when 'personnePhysique'
                  when 'personneMorale'
                    content_object.each do |personneMorale_legend, personneMorale_object|
                      case personneMorale_legend
                      when 'adresseEntreprise'
                        personneMorale_object.each do |address_legend, address_object|
                          case address_legend
                          when 'caracteristiques'
                          when 'adresse'
                            datum[:registered_address] = process_address(address_object)
                          when 'entrepriseDomiciliataire'
                          else
                            raise "Unhandled address legend: #{address_legend}"
                          end
                        end
                      when 'etablissementPrincipal'
                        personneMorale_object.each do |etablissementPrincipal_legend, etablissementPrincipal_object|
                          case etablissementPrincipal_legend
                          when "descriptionEtablissement"
                            etablissementPrincipal_object.each do |descriptionEtablissement_legend, descriptionEtablissement_object|
                              case descriptionEtablissement_legend
                              when 'rolePourEntreprise'
                              when 'siret'
                              when 'enseigne'
                              when 'nomCommercial'
                                datum[:alternative_names] =  [ { company_name: descriptionEtablissement_object, type: 'trading' } ]
                              when 'dateEffetFermeture'
                                datum[:dissolution_date] = descriptionEtablissement_object
                              when 'pays'
                              when 'activiteNonSedentaire'
                              when 'indicateurEtablissementPrincipal'
                              when 'codePays'
                              when 'indicateurEtranger'
                              when "indicateurDomiciliataire"
                              when "sansActiviteAutreActiviteSiege"
                              when "dateEffet"
                              when "indicateurEtranger"
                              when "indicateurDomiciliataire"
                              when "sansActiviteAutreActiviteSiege"
                              when "dateEffet"
                              when "indicateurEtranger"
                              when "indicateurDomiciliataire"
                              when "sansActiviteAutreActiviteSiege"
                              when "dateEffet"
                              else
                                puts "Unknown description legend  : #{descriptionEtablissement_legend}"
                              end
                            end
                          when "adresse"
                          when "activites"
                            next if etablissementPrincipal_object.blank?
                            etablissementPrincipal_object[0].each do |activities_legend,activites_object|
                              case activities_legend
                              when 'descriptionDetaillee'
                                datum[:all_attributes][:business_desctiption] = activites_object
                              end
                            end
                          when "nomsDeDomaine"
                          when 'activiteNonSedentaire'
                          when 'indicateurEtablissementPrincipal'
                          when 'domiciliataire'
                          when 'effectifSalarie'
                          when 'detailCessationEtablissement'
                          when 'registreAnterieur'
                          else
                            puts "Unknown etablissementPrincipal_legend : #{etablissementPrincipal_legend}"
                          end
                        end
                      when 'autresEtablissements'
                        next if personneMorale_object.blank?
                        personneMorale_object.each do |autres|
                          autres.each do |autresEtablissements_legend, autresEtablissements_object|
                            case autresEtablissements_legend
                            when 'adresse'
                            end
                          end
                        end
                      when 'detailCessationEntreprise'
                      when 'beneficiairesEffectifs'
                        personneMorale_object.each do |beneficiairesEffectifs_legend, beneficiairesEffectifs_object|
                          case beneficiairesEffectifs_legend
                          when 'beneficiaire'
                            beneficiairesEffectifs_object.each do |beneficiaire_legend, beneficiaire_object|
                              case beneficiaire_legend
                              when 'descriptionPersonne'
                                beneficiaire_object.each do |descriptionPersonne_legend, descriptionPersonne_object|
                                  case descriptionPersonne_legend
                                  when 'dateDeNaissance'
                                    data_hash = {"month"=> descriptionPersonne_object.split("-")[1], "year"=> descriptionPersonne_object.split("-")[0] }
                                    datum[:controlling_entities][:date_of_birth] =  data_hash
                                  when 'nom'
                                    controlling_entities_name << descriptionPersonne_object[0]
                                  when 'prenoms'
                                    controlling_entities_name << descriptionPersonne_object[0]
                                    datum[:controlling_entities][:name] = controlling_entities_name
                                  when 'nationalite'
                                    datum[:controlling_entities][:nationality] = descriptionPersonne_object
                                    datum[:controlling_entities][:entity_type] = "Person"
                                    datum[:controlling_entities][:confidence] = "HIGH"
                                    datum[:controlling_entities][:source_url] = "https://data.inpi.fr/entreprises/#{input["siren"]}"
                                  else
                                    puts "Unknown descriptionPersonne_legend : #{descriptionPersonne_legend}"
                                  end
                                end
                              when 'adresseDomicile'
                              end
                            end
                          when 'modalite'
                          end
                        end
                      when 'observations'
                        personneMorale_object.each do |observations_legend, observations_object|
                          case observations_legend
                          when 'rcs'
                            observations_object.each do |filings|
                              unless filings["numObservation"].blank?
                                filings_hash = {}
                                filings_hash[:uid] = filings["numObservation"]
                                filings_hash[:date] = filings["dateAjout"] || ""
                                filings_hash[:description] = filings["texte"]
                                datum[:filings] << filings_hash.snap if valid_filing?(filings_hash)
                              end
                            end
                          end
                        end
                      when 'identite'
                        personneMorale_object.each do |identity_legend, identity_object|
                          case identity_legend
                          when 'entreprise'
                            identity_object.each do |entreprise_legend, entreprise_object|
                              case entreprise_legend
                              when "siren"
                              when "denomination"
                                datum[:name] = entreprise_object
                              when "formeJuridique"
                                datum[:company_type] = COMPANY_TYPE[entreprise_object]
                              when "codeApe"
                                industry_code[:code] = entreprise_object
                                industry_code[:code_scheme_id] = "fr_naf_2008"
                                industry_code[:code_scheme_name] = "Nomenclature d'act (2008)"
                                industry_code[:description] = DESCRIPTION[entreprise_object]
                                datum[:industry_codes] << industry_code
                              when "dateImmat"
                                datum[:incorporation_date] = entreprise_object
                              when 'indicateurAssocieUnique'
                              when 'origineId'
                              when 'effectifSalarie'
                              when 'effectifApprenti'
                              when 'dateDebutActiv'
                              when 'nicSiege'
                              when 'nomCommercial'
                              when 'numDetenteur'
                              when 'numExploitant'
                              when 'numRna'
                              else
                                raise "Unhandled entreprise legend: #{entreprise_legend}"
                              end
                            end
                          when 'description'
                            identity_object.each do |description_legend, description_object|
                              case description_legend
                              when 'montantCapital'
                                datum[:total_shares][:number] = description_object.to_i
                              end
                            end
                          when 'nomsDeDomaine'
                          when 'entreprisesIntervenant'
                          when 'contratDAppui'
                          when 'publicationLegale'
                          when 'contratDAppuiDeclare'
                          else
                            raise "Unhandled identity legend: #{identity_legend}"
                          end
                        end 
                      when 'composition'
                        personneMorale_object.each do |composition_legend, composition_object|
                          case composition_legend
                          when "pouvoirs"
                            next if composition_object.blank?
                            composition_object.each do |pouvoirs_records|
                              officer_hash = { other_attributes: {} }
                              enterprise_officer_hash = {other_attributes: {}}
                              name_array = []
                              pouvoirs_records.each do |pouvoirs_legend,pouvoirs_object|
                                case pouvoirs_legend
                                when 'individu'
                                  pouvoirs_object.each do |individu_legend, individu_object|
                                    case individu_legend
                                    when 'descriptionPersonne'
                                      individu_object.each do |descriptionPersonne_legend, descriptionPersonne_object|
                                        case descriptionPersonne_legend
                                        when "dateDeNaissance"
                                          officer_hash[:other_attributes][:date_of_birth] = descriptionPersonne_object
                                        when "role"
                                        when "nom"
                                          name_array << descriptionPersonne_object
                                          officer_hash[:position] = "representative"
                                          officer_hash[:other_attributes][:type] = "Person"
                                        when "prenoms"
                                          name_array << descriptionPersonne_object
                                          officer_hash[:name] = name_array.join(" ").titleize
                                        when "nationalite"
                                          officer_hash[:other_attributes][:nationality] = descriptionPersonne_object
                                        when "situationMatrimoniale"
                                        else
                                        end
                                      end
                                    when 'adresseDomicile'
                                      individu_object.each do |addressPersonne_legend, addressPersonne_object|
                                        case addressPersonne_legend
                                          when "pays"
                                            officer_hash[:other_attributes][:country] = addressPersonne_object
                                          when "codePostal"
                                            officer_hash[:other_attributes][:postal_code] = addressPersonne_object
                                          when "commune"
                                            officer_hash[:other_attributes][:locality] = addressPersonne_object
                                          else
                                        end
                                      end
                                    when 'conjoint'
                                    else
                                    end
                                    datum[:officers] << officer_hash
                                  end
                                when 'entreprise'
                                  pouvoirs_object.each do |entreprise_officer_legend,entreprise_officer_object|
                                    case entreprise_officer_legend
                                    when 'denomination'
                                      enterprise_officer_hash[:name] = pouvoirs_object['denomination']
                                      enterprise_officer_hash[:position] = "representative"
                                      enterprise_officer_hash[:other_attributes][:type] = "Company"
                                    end
                                  end
                                when 'adresseEntreprise'
                                  pouvoirs_object.each do |adresseEntreprise_legend, adresseEntreprise_object|
                                    case adresseEntreprise_legend
                                      when "pays"
                                        enterprise_officer_hash[:other_attributes][:country] = adresseEntreprise_object
                                      when "codePostal"
                                        enterprise_officer_hash[:other_attributes][:postal_code] = adresseEntreprise_object
                                      when "commune"
                                        enterprise_officer_hash[:other_attributes][:locality] = adresseEntreprise_object
                                      when "voie"
                                        enterprise_officer_hash[:other_attributes][:street_address] = adresseEntreprise_object
                                        datum[:officers] << enterprise_officer_hash
                                      else
                                    end
                                  end
                                when 'representant'
                                when 'indicateurActifAgricole'
                                when 'qualiteArtisan'
                                else
                                  raise "Unhandled pouvoirs legend: #{pouvoirs_legend}"
                                end
                              end
                            end
                          else
                            raise "Unhandled composition legend: #{composition_legend}"
                          end
                        end
                      when 'structureEntreprise'
                      else
                        raise "Unhandled personneMorale legend: #{personneMorale_legend}"
                      end
                    end
                  when 'exploitation'
                  when 'natureCessation'
                  when 'registreAnterieur'
                  when 'succursaleOuFiliale'
                  when 'indicateurPoursuiteCessation'
                  else
                    raise "Unhandled content legend: #{content_legend}"
                  end
                end
              when 'typePersonne'
                datum[:all_attributes][:typePersonne] = formality_object
              when 'diffusionCommerciale'
              when 'historique'
              when 'formeJuridique'
              when 'created'
              when 'updated'
              else
                raise "Unhandled formality legend: #{formality_legend}"
              end
            end
          when 'siren'
            datum[:company_number] = object
          when 'updatedAt'
            datum[:all_attributes][:source_updated_at] = object
          else
            raise "Unhandled legend: #{legend}"
          end
        end
        return nil if datum.blank?

        datum[:all_attributes].snap
        IO.write('tmp/transformed.json', JSON.pretty_generate(datum.snap))
        return nil if datum[:name].blank?
        return nil if datum[:company_number].blank?
        datum[:officers]&.delete_if {|officer| officer[:name].blank? || officer[:name][/#{INVALID_OFFICER}/]}
        datum.snap
      rescue RuntimeError
        IO.write('tmp/invalid_parsed.json', JSON.pretty_generate(input))
        raise
      end
    end
  end
end

require 'openc_bot'
require 'openc_bot/pseudo_machine_company_fetcher_bot'

require_relative 'common'
require_relative 'fetcher'
require_relative 'parser'
require_relative 'transformer'

module FrCompaniesFetcher
  extend OpencBot
  extend OpencBot::PseudoMachineCompanyFetcherBot
  extend self
  file_path = 'fr_naf.yml'
  yaml_content = YAML.load_file(file_path)
  NAF_HASH = yaml_content.each_with_object({}) { |entry, hash| hash[entry[:code]] = entry[:name] }

  INVALID_OFFICER = Regexp.compile('^[^[:alnum:]]+$').freeze
end

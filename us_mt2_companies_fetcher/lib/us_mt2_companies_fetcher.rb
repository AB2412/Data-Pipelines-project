require 'openc_bot'
require 'openc_bot/pseudo_machine_company_fetcher_bot'
require 'byebug'

require_relative 'common'
require_relative 'fetcher'
require_relative 'parser'
require_relative 'transformer'

module UsMt2CompaniesFetcher
  extend OpencBot
  extend OpencBot::PseudoMachineCompanyFetcherBot
  extend self

  INVALID_OFFICER = Regexp.compile('^[^[:alnum:]]+$').freeze
end

# encoding: UTF-8
require 'mechanize'
require 'retriable'

class Mechanize
  class HTTP
    class Agent
      def fetch_with_retry(
        uri,
        method    = :get,
        headers   = {},
        params    = [],
        referer   = current_page,
        redirects = 0
      )
        log_info = proc do |exception, try, elapsed_time, next_interval|
          $stderr.puts "#{exception.class}: '#{exception.message}' - #{try} tries in #{elapsed_time} seconds and #{next_interval} seconds until the next try."
        end

        Retriable.retriable tries: 10, base_interval: 240, on_retry: log_info do
          fetch_without_retry(uri, method, headers, params, referer, redirects)
        end
      end

      # Alias so #fetch actually uses our new #fetch_with_retry to wrap the
      # old one aliased as #fetch_without_retry.
      alias fetch_without_retry fetch
      alias fetch fetch_with_retry
    end
  end
end

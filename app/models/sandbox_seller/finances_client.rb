require "base64"

module SandboxSeller
  # Stands in for Peddler's Finances 2024-06-19 client on sandbox seller syncs: answers listTransactions with
  # TransactionGenerator data, filtered by posted date and paginated with an opaque nextToken, without calling Amazon.
  class FinancesClient
    PAGE_SIZE = 100

    def initialize
      @years = {}
    end

    def list_transactions(posted_after:, posted_before: nil, next_token: nil, **)
      after = Time.iso8601(posted_after.to_s)
      before = posted_before.present? ? Time.iso8601(posted_before.to_s) : 2.minutes.ago
      offset = next_token.present? ? decode_offset(next_token) : 0

      matching = ((after.year - 1)..before.year).flat_map { |year| transactions_for(year) }
        .select { |transaction| (after...before).cover?(Time.iso8601(transaction["postedDate"])) }
      remaining = matching.drop(offset)

      payload = { "transactions" => remaining.first(PAGE_SIZE) }
      payload["nextToken"] = encode_offset(offset + PAGE_SIZE) if remaining.size > PAGE_SIZE
      { "payload" => payload }
    end

    private

    def transactions_for(year)
      @years[year] ||= TransactionGenerator.for_year(year)
    end

    def encode_offset(offset)
      Base64.urlsafe_encode64("sandbox-seller:#{offset}", padding: false)
    end

    def decode_offset(token)
      Base64.urlsafe_decode64(token.to_s).delete_prefix("sandbox-seller:").to_i
    rescue ArgumentError
      raise AmazonSpApi::Error, "Invalid nextToken."
    end
  end
end

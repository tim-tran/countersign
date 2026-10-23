require "digest"
require "json"

module Ledger
  # Fingerprint of a posting request, so a retried idempotency key can be
  # checked against what it originally asked for.
  module RequestHash
    def self.call(operation:, entries:, effective_at:, metadata:)
      payload = {
        "operation" => operation,
        "entries" => canonical_entries(entries),
        "effective_at" => effective_at.respond_to?(:iso8601) ? effective_at.utc.iso8601(6) : effective_at,
        "metadata" => deep_sort(metadata || {})
      }
      Digest::SHA256.hexdigest(JSON.generate(payload))
    end

    def self.canonical_entries(entries)
      entries
        .map { |e| e.to_h.transform_keys(&:to_s).slice("account_code", "direction", "amount_minor") }
        .sort_by { |e| [ e["account_code"].to_s, e["direction"].to_s, e["amount_minor"].to_i ] }
        .map { |e| deep_sort(e) }
    end

    def self.deep_sort(value)
      case value
      when Hash then value.to_h { |k, v| [ k.to_s, deep_sort(v) ] }.sort.to_h
      when Array then value.map { |v| deep_sort(v) }
      else value
      end
    end
  end
end

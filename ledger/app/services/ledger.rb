module Ledger
  class Error < StandardError; end
  class InvalidRequest < Error; end
  class NotFound < Error; end
  class Unbalanced < Error; end
  class CurrencyMismatch < Error; end
  class InsufficientFunds < Error; end
  class ConflictError < Error; end
  class InvalidState < Error; end
end

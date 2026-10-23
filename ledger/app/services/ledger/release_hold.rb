module Ledger
  # Frees an active hold without posting anything. Releasing a released hold
  # is a no-op; releasing a captured hold is an invalid transition.
  class ReleaseHold
    def self.call(...)
      new(...).call
    end

    def initialize(hold_id:)
      @hold_id = hold_id
    end

    def call
      ApplicationRecord.transaction do
        # Lock order: hold row first, then its balance row.
        hold = Hold.lock("FOR UPDATE").find_by(id: @hold_id)
        raise NotFound, "unknown hold #{@hold_id.inspect}" unless hold
        next hold if hold.status == "released"
        raise InvalidState, "hold #{hold.id} is #{hold.status}, cannot release" unless hold.status == "active"

        balance = AccountBalance.lock("FOR UPDATE").find(hold.account_id)
        balance.held_minor -= hold.amount_minor
        balance.version += 1
        balance.save!
        hold.update!(status: "released")
        hold
      end
    end
  end
end

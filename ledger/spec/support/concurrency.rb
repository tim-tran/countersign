module ConcurrencyHelpers
  # Runs the block in `count` threads released together. Returns each block's
  # value, or the exception it raised, in thread-index order.
  def run_concurrently(count)
    gate = Queue.new
    ready = Queue.new

    threads = Array.new(count) do |i|
      Thread.new do
        ActiveRecord::Base.connection_pool.with_connection do
          ready << true
          gate.pop
          yield i
        rescue StandardError => e
          e
        end
      end
    end

    count.times { ready.pop }
    count.times { gate << true }
    threads.map(&:value)
  end
end

RSpec.configure do |config|
  config.include ConcurrencyHelpers
end

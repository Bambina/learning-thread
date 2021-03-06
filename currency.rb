#SizedQueue can communiacte with the threads correctly with ruby 2.1.3 version
#SizedQueue doesn't communiacte correctly with ruby 2.1.0 version
#a related ruby-trunk - Bug #9343 ??
require 'thread'
require 'monitor'
require 'net/http'

class CurrencyDownloader
  class << self
    def download_currencies
      start = Time.now

      currencies =
        ['USD', 'CAD', 'HKD', 'EUR', 'JPY', 'AUD', 'CNY', 'DEM', 'GBP', 'ILS', 'INR', 'XAU', 'XAG']

      threads_count = 5
      threads = Array.new(threads_count)

      #it is distributed following currencies by producer fiber
      work_queue = Queue.new

      #a monitor can remind when a thread finishes then we can schedule a new one
      threads.extend(MonitorMixin)
      threads_available = threads.new_cond

      #it tells when a thred can resume after scheduling
      sysexit = false

      results = Array.new

      #it's for the shared results array
      results_mutex = Mutex.new

      consumer_fib = Fiber.new do
        loop do
          Fiber.yield if work_queue.length == 0

          found_index = nil
          threads.synchronize do #lock and access shared resource(threads[])
            threads_available.wait_while do
              #collects threads which are nil or having false status or finished
              #resumes if sum is not 0
              threads.select { |thread| thread.nil? || thread.status == false  ||
                thread["finished"].nil? == false}.length == 0
            end

            found_index = threads.rindex { |thread| thread.nil? || thread.status == false ||
              thread["finished"].nil? == false }
          end
          #キューから取り出してスレッドを作り実行する。
          #signalをたたいてthreads[]配列に要素が追加されたことを通知する。
          following_currency = work_queue.pop
          threads[found_index] = Thread.new(following_currency) do
            results_mutex.synchronize do
              results << Net::HTTP.get("download.finance.yahoo.com",
                "/d/quotes.csv?e=.csv&f=sl1d1t1&s=USD#{following_currency}=X")
            end
            Thread.current["finished"] = true
            threads.synchronize do
              threads_available.signal
            end
          end
        end
      end

      producer_fib = Fiber.new do
        currencies.each do |currency|
          work_queue << currency
          Fiber.yield if work_queue.length == 5
        end
        sysexit = true
      end

      until sysexit == true && work_queue.length == 0
        producer_fib.resume
        consumer_fib.resume
      end

      threads.each do |thread|
          thread.join unless thread.nil?
      end

      p "DONE------- #{Time.now - start} secs"
      puts results
      p "#{results.length} currencies returned."
      results
    end
  end
end

loop do
  Thread.new do
    downloaded_currencies = Array.new
    downloaded_currencies << CurrencyDownloader.download_currencies
  end
  sleep 10
end



namespace :fetch do
  desc 'Run the fetcher for bloomberg.com'
  task(:stocks) do
    require 'benchmark'
    require 'fetcher'
    run_fetcher_and_create_list
  end
end

private

# Run the fetcher and save the list of ISINS.
#
# @return [ Array<String> ] List of fetched ISIN numbers.
def run_fetcher_and_create_list
  puts 'Fetching stocks from bloomberg.com...'

  stocks = []
  time   = Benchmark.realtime { stocks = Fetcher.new.run }

  puts "Fetched #{stocks.count} stocks from bloomberg.com"
  puts "Time elapsed #{time.round(2)} seconds"

  create_list(stocks, 'tmp/stocks.txt')
rescue StandardError => e
  $stderr.puts "#{e.class}: #{e.message}"
end

# Save the provided list of ISINS in a text file at the provided path.
#
# @param [ Array<String> ] List of fetched ISIN numbers.
# @param [ String ] path The folder where to place the list.
def create_list(stocks, path = 'tmp')
  FileUtils.mkdir_p File.dirname(path)
  File.open(path, 'w+') { |f| stocks.each { |stock| f << "#{stock}\n" } }
  puts "Placed stocks under #{path}"
end

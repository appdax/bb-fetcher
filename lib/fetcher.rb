require 'open-uri'
require 'nokogiri'
require 'typhoeus'
require 'yaml'

# The `Fetcher` class scrapes symbol lookup page of bloomberg.com to get a list
# of all stock ticker symbols. In case of a paginated response it follows all
# subsequent linked pages.
#
# @example Get a list of all tickers.
#   run
#   #=> [412:HK, 8439:JP, CGF:AU, ...]
#
# @example Get a list of all stock tickers.
#   run(type: 'Common Stock')
#   #=> [412:HK, 8439:JP, CGF:AU, ...]
#
# @example Fetch AGs (Aktiengesellschaften) only.
#   run(type: 'Common Stock', abbrevs: 'AG')
#   #=> [SAP:GR]
#
# @example Get a list of all linked sub-result pages.
#   linked_pages('bloomberg.com/markets/symbolsearch?query=A')
#   #=> ['bloomberg.com/markets/symbolsearch?query=A&page=2',
#        'bloomberg.com/markets/symbolsearch?query=A&page=3', ...]
#
# @example Find out if the list is paginated.
#   follow_linked_pages? 'bloomberg.com/markets/symbolsearch?query=A'
#   #=> true
class Fetcher
  # Default abbreviations to search for.
  ABBREVIATIONS ||= YAML.load_file('lib/data/abbreviations.yaml').freeze

  # Intialize the fetcher.
  #
  # @return [ PreFetcher ] A new fetcher instance.
  def initialize
    @hydra  = Typhoeus::Hydra.new
    @stocks = []
  end

  # The type of the stock to look for when searching for ticker symbols.
  #
  # @example Fetch only equity indexes.
  #   type('Equity Index')
  #   #=> self
  #
  # @example Fetch any type.
  #   type(/.?/)
  #   #=> self
  #
  # @example Get the assigned type.
  #   type
  #   #=> /Stock$/
  #
  # @param [ String|Regex ] type Optional for assignment.
  #
  # @return [ String|Regex ] Defaults to: /Stock$/
  def type(type = nil)
    @type = type if type
    @type ||= /Stock$/

    type.nil? ? @type : self
  end

  # Accessor for the abbreviations to look for.
  # See Fetcher::ABBREVIATIONS for the default list.
  #
  # @example Limit to AGs (Aktiengesellschaften)
  #   abbrevs('AG')
  #   #=> self
  #
  # @example Get the assigned abbreviations.
  #   abbrevs
  #   #=> ['Ltd', 'Corp', 'AG', ...]
  #
  # @param [ Array<String> ] abbrevs Optional assignment.
  #
  # @return [ Array<String> ] Defaults to: ABBREVIATIONS
  def abbrevs(abbrevs = nil)
    list = abbrevs.compact if abbrevs

    @abbrevs   = list if list
    @abbrevs ||= ABBREVIATIONS.dup

    list.nil? ? @abbrevs : self
  end

  # Extract all stock tickers found inside the table with type `Common Stock`.
  #
  # @example
  #   stocks(page)
  #   # => ["AAPL:US", "AMZN:US", "ABI:BB", "GOOGL:US", "GOOG:US", "AMGN:US"]
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page.
  #
  # @return [ Array<String> ] List of containig ticker symbols.
  def stocks(page)
    sel = '#primary_content > div.symbol_search > table tr:not(.data_header)'

    page.css(sel)
        .select { |tr| tr.at_css('td:nth-child(4) text()').text.match(type) }
        .map! { |tr| tr.at_css('td.symbol a text()').text }
  end

  # Determine whether the fetcher has to follow linked lists in case of
  # pagination. To follow is only required if the URL of the response
  # does not include the `page` query attribute.
  #
  # @example Follow paginating of the 1st result page.
  #   follow_linked_pages? 'bloomberg.com/markets/symbolsearch?query=A'
  #   #=> true
  #
  # @example Follow paginating of the 2nd result page.
  #   follow_linked_pages? 'bloomberg.com/markets/symbolsearch?query=A&page=2'
  #   #=> false
  #
  # @param [ String ] url The URL of the HTTP request.
  #
  # @return [ Boolean ] true if the linked pages have to be scraped as well.
  def follow_linked_pages?(url)
    url !~ /page=/
  end

  # Scrape all linked lists found on the specified search result page.
  #
  # @example
  #   linked_pages('bloomberg.com/markets/symbolsearch?query=A')
  #   #=> ['bloomberg.com/markets/symbolsearch?query=A&page=2',
  #        'bloomberg.com/markets/symbolsearch?query=A&page=3', ...]
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page.
  # @param [ String] The URL of the page.
  #
  # @return [ Array<String> ] List of URIs pointing to each linked page.
  def linked_pages(page, url = '')
    sel = '#primary_content > div.symbol_search > div.ticker_matches text()'
    lbl = page.at_css(sel).text.strip
    amount, total = lbl.scan(/(\d+) of (\d+)$/).flatten!.map!(&:to_f)

    return [] if amount == 0 || amount >= total

    (2..(total / amount).ceil).map { |site| "#{url}&page=#{site}" }
  rescue NoMethodError
    []
  end

  # Run the hydra to scrape all sectors first, then each industries per sector
  # and finally all stocks per industry to get their exchance ticker.
  #
  # @example Fetch all stocks for all regions.
  #   run
  #   #=> [412:HK, 8439:JP, CGF:AU, ...]
  #
  # @example Fetch all common stocks.
  #   run(type: 'Common Stock')
  #   #=> [412:HK, 8439:JP, CGF:AU, ...]
  #
  # @example Fetch AGs (Aktiengesellschaften) only.
  #   run(type: 'Common Stock', abbrevs: 'AG')
  #   #=> [SAP:GR]
  #
  # @param [ String ] type Optional type assignment.
  # @param [ String ] abbrevs Optional assignment of abbreviations.
  #
  # @return [ Array<String> ] Array of stock tickers.
  def run(type: nil, abbrevs: nil)
    type(type)
    abbrevs(abbrevs)

    self.abbrevs.each do |abbr|
      scrape abs_url("markets/symbolsearch?query=#{abbr}")
    end

    @hydra.run
    @stocks.uniq { |sym| sym.scan(/^[^:]*/)[0] }
  ensure
    @stocks.clear
  end

  private

  # Add the specified link to the hydra and invoke the callback once
  # the response is there.
  #
  # @example Scrape all stocks including the letter 'A'.
  #   scrape 'http://www.bloomberg.com/markets/symbolsearch?query=A'
  #
  # @param [ String ] url An absolute URL of a page with search results.
  #
  # @return [ Void ]
  def scrape(url)
    req = Typhoeus::Request.new(url)

    req.on_complete(&method(:on_complete))

    @hydra.queue req
  end

  # Final callback of the `scrape` method that extracts the ticker symbol from
  # the page of a stock.
  #
  # @param [ Typhoeus::Response ] res The response of the HTTP request.
  #
  # @return [ Void ]
  def on_complete(res)
    return unless res.success?

    begin
      page   = Nokogiri::HTML(res.body)
      stocks = stocks(page)

      @stocks.concat(stocks) if stocks
    ensure
      url = res.effective_url
      linked_pages(page, url).each { |p| scrape p } if follow_linked_pages? url
    end
  end

  # Add host and protocol to the URI to be absolute.
  #
  # @example
  #   abs_url('quote/AMZ:GR')
  #   #=> 'https://www.bloomberg.com/quote/AMZ:GR'
  #
  # @param [ String ] A relative URI.
  #
  # @return [ String ] The absolute URI.
  def abs_url(url)
    "http://www.bloomberg.com/#{url}"
  end
end

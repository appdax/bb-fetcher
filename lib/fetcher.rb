require 'open-uri'
require 'nokogiri'
require 'typhoeus'

# The `Fetcher` class scrapes bloomberg.com to get a list of all stocks.
# To do so it extracts all sectors from the search form to make a 2nd request
# to get all industries per sector. For each industry it extracts the tickers
# of each containing company. In case of a paginated response it follows all
# subsequent linked pages.
#
# @example Fetch all stocks.
#   run
#   #=> [412:HK, 8439:JP, CGF:AU, ...]
#
# @example Fetch stocks from US only.
#   run(regions: 'US')
#   # => [GAS:US, ATO:US]
#
# @example Get a list of all sectors.
#   sectors
#   #=> ['sectors/sectordetail.asp?code=25',
#        'sectors/sectordetail.asp?code=30']
#
# @example Get all industries from energy sector.
#   industries('sectors/sectordetail.asp?code=25')
#   #=> ['industries/industrydetail.asp?code=1010',
#        'industries/industrydetail.asp?code=1020']
#
# @example Get all companies from transportation industry.
#   industries('industries/industrydetail.asp?code=203020')
#   # => ['stocks/snapshot/snapshot.asp?capid=6491293',
#         'stocks/snapshot/snapshot.asp?capid=248501']
class Fetcher
  # Intialize the fetcher.
  #
  # @return [ PreFetcher ] A new fetcher instance.
  def initialize
    @hydra  = Typhoeus::Hydra.new
    @stocks = []
  end

  # Bloomberg devides sectors and industries into regions like US or Europe.
  # Get or limit the regions to focus on.
  #
  # @example Limit regions to Europe and Asia only.
  #   regions :Europe, :Asia
  #   # => [:Europe, :Asia]
  #
  # @example List regions only.
  #   regions
  #   # => [:Americas, :Europe, :Asia, :MidEastAfr]
  #
  # @return [ Array<String> ]
  def regions(*regions)
    @regions = regions.flatten if regions && regions.any?
    @regions ||= %w(Americas Europe Asia MidEastAfr)
  end

  # List of all sectors.
  #
  # @example
  #   sectors
  #   #=> ['sectors/sectordetail.asp?code=25',
  #        'sectors/sectordetail.asp?code=30']
  #
  # @return [ Array<String> ] List of absolute URLs
  def sectors
    url  = abs_url('overview/sectorlanding.asp')
    page = Nokogiri::HTML(open(url))

    page.css('#sectorTable h3 a').map { |link| abs_url link[:href][3..-1] }
  rescue Timeout::Error
    []
  end

  # List of all industries of the specified sector.
  #
  # @example Get all industries for energy sector.
  #   industries('sectors/sectordetail.asp?code=25')
  #   #=> ['industries/industrydetail.asp?code=1010',
  #        'industries/industrydetail.asp?code=1020']
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page of a sector.
  #
  # @return [ Array<String> ] List of absolute URLs.
  def industries(page)
    sel = '#columnLeft > div.mb20 > table > tbody > tr > td:nth-child(1) > a'

    page.css(sel).map { |link| abs_url link[:href][3..-1] }
  end

  # List of all companies found within the search result page.
  #
  # @example Get all companies for the transportation industry.
  #   industries('industries/industrydetail.asp?code=203020')
  #   # => ['stocks/snapshot/snapshot.asp?capid=6491293',
  #         'stocks/snapshot/snapshot.asp?capid=248501']
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page of a sector.
  #
  # @return [ Array<String> ] List of absolute URLs.
  def companies(page)
    sel = '#columnLeft > div:nth-child(10) > table > tbody > tr > td:nth-child(1) > a.link_s' # rubocop:disable Metrics/LineLength
    str = '/sectorandindustry/..'

    page.css(sel).map { |link| abs_url(link[:href][3..-1]).sub!(str, '') }
  end

  # Extract the ticker from the page.
  #
  # @example Ticker symbol from facebook page.
  #   ticker(page)
  #   # => 'FB2A:GR'
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page.
  # @param [ String ] url Optional URL which contains the ticker symbol.
  #
  # @return [ Array<String> ] Ticker symbol.
  def ticker(page, url = nil)
    sym = url.scan(/[A-Z]*:[A-Z]*$/).first if url

    return sym if sym

    sel = '#rrQuoteBox table tr > td:nth-child(1) > a text()'
    sym = page.at_css(sel)

    unless sym
      sel = '#content div.basic-quote div.ticker-container div.ticker text()'
      sym = page.at_css(sel)
    end

    sym.text.strip if sym
  end

  # Determine whether the fetcher has to follow linked lists in case of
  # pagination. To follow is only required if the URL of the response
  # does not include the `firstrow` query attribute.
  #
  # @example Follow paginating of the 1st result page of semiconductor industry.
  #   follow_linked_pages? 'industrydetail.asp?code=453010'
  #   #=> true
  #
  # @example Follow paginating of the 2nd result page of semiconductor industry.
  #   follow_linked_pages? 'industrydetail.asp?code=453010&firstrow=20'
  #   #=> false
  #
  # @param [ String ] url The URL of the HTTP request.
  #
  # @return [ Boolean ] true if the linked pages have to be scraped as well.
  def follow_linked_pages?(url)
    url !~ /firstrow/
  end

  # Scrape all linked lists found on the specified search result page.
  #
  # @example Linked pages of the semiconductor industry.
  #   linked_pages('industries/industrydetail.asp?code=453010')
  #   #=> ['industrydetail.asp?code=453010&firstrow=20',
  #        'industrydetail.asp?code=453010&firstrow=40']
  #
  # @param [ Nokogiri::HTML ] page A parsed search result page.
  #
  # @return [ Array<String> ] List of URIs pointing to each linked page.
  def linked_pages(page)
    sel = '#columnLeft div.paging a.link'
    page.css(sel).map { |link| abs_url "industries/#{link['href']}" }
  end

  # Run the hydra to scrape all sectors first, then each industries per sector
  # and finally all stocks per industry to get their exchance ticker.
  #
  # @example Scrape all stocks for all regions.
  #   run
  #   #=> [412:HK, 8439:JP, CGF:AU, ...]
  #
  # @example Scrape stocks from US only.
  #   run(regions: 'US')
  #   # => [GAS:US, ATO:US]
  #
  # @param [ Array<String> ] regions A subset of Boombergs regions.
  #                                  Defaults to: All available regions.
  #
  # @return [ Array<String> ] Array of stock tickers.
  def run(regions: nil)
    self.regions(*regions) if regions
    scrape_sectors

    @hydra.run
    @stocks.dup
  ensure
    @stocks.clear
  end

  private

  # Iterate over all sectors and scrape their industries.
  #
  # @return [ Void ]
  def scrape_sectors
    sectors.each { |url| scrape url, :scrape_industries }
  end

  # Iterate over all industies and scrape their companies.
  #
  # @param [ Typhoeus::Response ] res The response of the HTTP request.
  #
  # @return [ Void ]
  def scrape_industries(res)
    return unless res.success?

    page  = Nokogiri::HTML(res.body)
    uris  = industries(page)

    uris.each { |industry| scrape_companies(industry) }
  end

  # Scrape the companies of that industry within each region.
  #
  # @param [ String ] url The URL of an industry.
  #
  # @return [ Void ]
  def scrape_companies(url)
    regions.each { |region| scrape "#{url}&region=#{region}", :scrape_tickers }
  end

  # Iterate over all industies and scrape their companies.
  #
  # @param [ Typhoeus::Response ] res The response of the HTTP request.
  #
  # @return [ Void ]
  def scrape_tickers(res)
    return unless res.success?

    page = Nokogiri::HTML(res.body)
    uris = companies(page)

    uris.each { |uri| scrape uri }

    return unless follow_linked_pages? res.effective_url

    linked_pages(page).each { |site| scrape site, :scrape_tickers }
  end

  # Final callback of the `scrape` method that extracts the ticker symbol from
  # the page of a stock.
  #
  # @param [ Typhoeus::Response ] res The response of the HTTP request.
  #
  # @return [ Void ]
  def on_complete(res)
    url = res.effective_url

    return if url =~ /stocks$/

    page   = Nokogiri::HTML(res.body)
    ticker = ticker(page, url)

    @stocks << ticker if ticker
  end

  # Add the specified link to the hydra and invoke the callback once
  # the response is there.
  #
  # @example Scrape all industries of the energy sector.
  #   scrape 'sectors/sectordetail.asp?code=10', :scrape_industries
  #
  # @param [ String ] url An absolute URL of a page with search results.
  # @param [ Symbol ] calback The name of the callback method.
  #
  # @return [ Void ]
  def scrape(url, callback = :on_complete)
    req = Typhoeus::Request.new(url, followlocation: true)

    req.on_complete(&method(callback))

    @hydra.queue req
  end

  # Add host and protocol to the URI to be absolute.
  #
  # @example
  #   abs_url('overview/sectorlanding.asp')
  #   #=> 'http://www.bloomberg.com/research/sectorandindustry/overview/sectorlanding.asp'
  #
  # @param [ String ] A relative URI.
  #
  # @return [ String ] The absolute URI.
  def abs_url(url)
    "http://www.bloomberg.com/research/sectorandindustry/#{url}"
  end
end

RSpec.describe Fetcher do
  let(:search_url) { 'http://www.bloomberg.com/markets/symbolsearch' }
  let(:fetcher) { described_class.new }
  subject { fetcher }

  describe '::ABBREVIATIONS' do
    subject { described_class::ABBREVIATIONS }
    it { is_expected.to be_frozen }
  end

  describe '#type' do
    subject { fetcher.type }
    it('should have a default value') { is_expected.to_not be_nil }

    context 'when setting a new type' do
      subject { fetcher.type('A') }
      it('should return self') { is_expected.to be(fetcher) }

      context 'when asking for the type' do
        subject { fetcher.type }
        before { fetcher.type('A') }
        it('should return the type') { is_expected.to eq('A') }
      end
    end
  end

  describe '#abbrevs' do
    subject { fetcher.abbrevs }
    it('should have a default value') { is_expected.to_not be_nil }

    context 'when setting abbreviations' do
      subject { fetcher.abbrevs(['AG']) }
      it('should return self') { is_expected.to be(fetcher) }

      context 'when asking for the abbreviations' do
        subject { fetcher.abbrevs }
        before { fetcher.abbrevs(['AG']) }
        it('should return the abbreviations') { is_expected.to eq(['AG']) }
      end
    end
  end

  describe '#follow_linked_pages?' do
    subject { fetcher.follow_linked_pages? url }

    context 'when its the head of the list' do
      let(:url) { "#{search_url}?query=siemens" }
      it { is_expected.to be_truthy }
    end

    context 'when its the tail of the list' do
      let(:url) { "#{search_url}?query=siemens&page=2" }
      it { is_expected.to be_falsy }
    end
  end

  describe '#linked_pages' do
    let(:page) { Nokogiri::HTML(content) }
    subject { fetcher.linked_pages page }

    context 'when page is empty' do
      let(:content) { '<html><body></body></html>' }
      it { is_expected.to be_empty }
    end

    context 'when page isnt paginated' do
      let(:content) { IO.read('spec/fixtures/empty.html') }
      it { is_expected.to be_empty }
    end

    context 'when page is paginated' do
      let(:content) { IO.read('spec/fixtures/paginated.html') }
      it { is_expected.to_not be_empty }
    end

    context 'when result set contains 7755 hits' do
      let(:count) { subject.count }
      let(:content) { IO.read('spec/fixtures/ag.html') }
      it { expect(count).to eq(387) }
    end
  end

  describe '#stocks' do
    let(:page) { Nokogiri::HTML(content) }
    subject { fetcher.stocks(page).count }

    context 'when page is empty' do
      let(:content) { '<html><body></body></html>' }
      it { is_expected.to be_zero }
    end

    context 'when list is empty' do
      let(:content) { IO.read('spec/fixtures/empty.html') }
      it { is_expected.to be_zero }
    end

    context 'when type is limit to `Common Stock`' do
      let(:content) { IO.read('spec/fixtures/paginated.html') }
      before { fetcher.type('Common Stock') }
      it { is_expected.to eq(5) }
    end

    context 'when type is limit to /Fund$/' do
      let(:content) { IO.read('spec/fixtures/paginated.html') }
      before { fetcher.type(/Fund$/) }
      it { is_expected.to eq(12) }
    end
  end

  describe '#run' do
    let(:stocks) { fetcher.run }
    subject { stocks.count }

    context 'when the network is offline' do
      before { stub_request(:get, /#{search_url}/).to_timeout }
      it { is_expected.to be_zero }
    end

    context 'when the service is not available' do
      before { stub_request(:get, /#{search_url}/).to_return status: 503 }
      it { is_expected.to be_zero }
    end

    context 'when the service responds with unexpected content' do
      before { stub_request(:get, /#{search_url}/).to_return body: '' }
      it { is_expected.to be_zero }
    end

    context 'when the service responds with 2 pages' do
      let(:content) { IO.read('spec/fixtures/paginated.html') }

      before do
        stub_request(:get, /\?query=AG$/).to_return body: content
        stub_request(:get, /page=2/).to_return status: 200

        fetcher.run abbrevs: ['AG']
      end

      it('should have requested 2 pages') do
        expect(a_request(:get, /query=AG/)).to have_been_made.times(2)
        expect(a_request(:get, /page=2/)).to have_been_made
      end

      context 'when fetching for type ADR' do
        subject { fetcher.run(type: 'ADR').count }
        it { is_expected.to eq(3) }
      end

      context 'when fetching for abbreviation AG' do
        subject { fetcher.run(abbrevs: ['AG']).count }
        it { is_expected.to eq(4) }
      end
    end
  end
end

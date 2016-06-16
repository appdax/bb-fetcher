require 'simplecov'
require 'webmock/rspec'
require 'codeclimate-test-reporter'
require 'pry'

WebMock.disable_net_connect!(allow: 'codeclimate.com')

CodeClimate::TestReporter.start

SimpleCov.start do
  add_filter '/spec'
  add_filter '/lib/extensions'
  formatter SimpleCov::Formatter::MultiFormatter.new(
    [
      SimpleCov::Formatter::HTMLFormatter,
      CodeClimate::TestReporter::Formatter
    ]
  )
end

Dir['lib/**/*.rb'].each { |f| require_relative "../#{f}" }

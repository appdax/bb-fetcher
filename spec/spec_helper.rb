require 'simplecov'
require 'webmock/rspec'
require 'pry'

WebMock.disable_net_connect!(allow: 'codeclimate.com')

SimpleCov.start do
  add_filter '/spec'
  add_filter '/lib/extensions'
end

Dir['lib/**/*.rb'].each { |f| require_relative "../#{f}" }

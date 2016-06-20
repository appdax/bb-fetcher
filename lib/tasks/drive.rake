
namespace :drive do
  desc 'Upload list for scraping'
  task(:upload) { upload_to_drive }

  desc 'Check accessibility of the external drive'
  task(:check) { drive && puts('OK') }
end

private

# Upload the list to Dropbox.
def upload_to_drive
  file = open('tmp/stocks.txt')
  res  = drive.put_file('bloomberg.stocks.txt', file, true)

  puts "Uploaded #{res['size']} as rev #{res['revision']}/#{res['rev']}"
rescue StandardError => e
  $stderr.puts "#{e.class}: #{e.message}"
end

# Dropbox client instance.
# Throws an error if authentification fails.
#
# @return [ DropboxClient ]
def drive
  require 'dropbox_sdk'
  @client ||= DropboxClient.new ENV['ACCESS_TOKEN']
end

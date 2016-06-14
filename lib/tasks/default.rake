
begin
  require 'rspec/core/rake_task'

  RSpec::Core::RakeTask.new(:spec) do |t|
    t.rspec_opts = '--format documentation --color --require spec_helper'
  end

  task default: :spec
rescue LoadError # rubocop:disable Lint/HandleExceptions
end

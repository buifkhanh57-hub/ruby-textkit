# frozen_string_literal: true

require 'rake/testtask'

Rake::TestTask.new(:test) do |t|
  t.libs << 'lib' << 'test'
  t.pattern = 'test/**/*_test.rb'
  t.warning = true
end

desc 'Run the full test suite (same as `rake` with no arguments)'
task default: :test

desc 'Print the gem identity (name, version, summary)'
task :about do
  require_relative 'lib/wordcraft/version'
  puts Wordcraft::Version.label
  puts Wordcraft::Version::SUMMARY
end

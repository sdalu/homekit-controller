# frozen_string_literal: true

require "rake/testtask"
require "rubocop/rake_task"

Rake::TestTask.new do |task|
    task.libs << "lib" << "test"
    task.pattern = "test/**/*_test.rb"
end

RuboCop::RakeTask.new

task default: %i[test rubocop]

desc "Open a session with a real accessory and count its accessories, " \
     "read only (HAP_PAIRING=path of an existing pairing)"
task :accessory do
    $LOAD_PATH.unshift(File.expand_path("lib", __dir__))
    require "homekit/controller"
    hap = HomeKit::Controller
    pairing = hap::Pairing.load(ENV.fetch("HAP_PAIRING"))
    hap::Client.open(pairing) { puts "#{it.accessories.size} accessories" }
end

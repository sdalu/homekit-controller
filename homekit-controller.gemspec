# frozen_string_literal: true

require_relative "lib/homekit/controller/version"

Gem::Specification.new do |s|
    s.name        = "homekit-controller"
    s.version     = HomeKit::Controller::VERSION
    s.authors     = ["Stéphane D'Alu"]
    s.email       = ["sdalu@sdalu.com"]

    s.summary     = "HomeKit Accessory Protocol controller, over IP"
    s.description = "The controller side of HomeKit (HAP over IP), what an " \
                    "iPhone does: pair with an accessory by its setup " \
                    "code, open an encrypted session, read and write " \
                    "characteristics, find accessories by mDNS, and drive " \
                    "thermostats. Standard library only (OpenSSL 3)."
    s.homepage    = "https://github.com/sdalu/homekit-controller"
    s.license     = "MIT"

    s.required_ruby_version = ">= 3.4"

    s.metadata = {
        "homepage_uri" => s.homepage,
        "rubygems_mfa_required" => "true"
    }

    s.files = Dir.chdir(__dir__) do
        Dir["{lib}/**/*", "LICENSE.txt", "README.md"]
            .reject { |f| File.directory?(f) }
    end

    s.require_paths = ["lib"]
end

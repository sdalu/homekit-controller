# frozen_string_literal: true

module HomeKit
    # The controller side of the HomeKit Accessory Protocol over IP: what
    # an iPhone does when it talks to an accessory on the local network.
    # It pairs (Client.pair), verifies and encrypts a session
    # (Client.open), reads and writes characteristics, finds accessories
    # by mDNS (Discovery), and reads thermostats (Thermostats).
    module Controller
        class Error               < StandardError; end
        class ProtocolError       < Error; end
        class AuthenticationError < Error; end
        class PairingError        < Error; end

        APPLE_UUID_SUFFIX = "-0000-1000-8000-0026BB765291"

        # "0000004A-0000-1000-8000-0026BB765291" and "4A" both give "4A".
        def self.short_type(type)
            head = type.upcase.delete_suffix(APPLE_UUID_SUFFIX)
            head.sub(/\A0+(?=.)/, "")
        end
    end
end

require "homekit/controller/version"
require "homekit/controller/crypto"
require "homekit/controller/tlv8"
require "homekit/controller/srp"
require "homekit/controller/transport"
require "homekit/controller/http"
require "homekit/controller/pairing"
require "homekit/controller/pair_setup"
require "homekit/controller/pair_verify"
require "homekit/controller/client"
require "homekit/controller/watch"
require "homekit/controller/discovery"
require "homekit/controller/thermostat"
require "homekit/controller/thermostats"

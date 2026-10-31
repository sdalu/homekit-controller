# frozen_string_literal: true

require "json"
require "socket"

module HomeKit
    module Controller
        # A verified, encrypted session with one paired accessory.
        class Client
            TIMEOUT         = 10
            # Pair-setup has the accessory run 3072-bit SRP arithmetic,
            # which a bridge's small CPU can take tens of seconds over.
            PAIRING_TIMEOUT = 90
            JSON_TYPE       = "application/hap+json"

            # Runs pair-setup and returns the Pairing to save.
            def self.pair(host, port, setup_code)
                socket = tcp(host, port, PAIRING_TIMEOUT)
                http = HTTP.new(Transport::Plain.new(socket), "#{host}:#{port}")
                identities = PairSetup.new(http, setup_code).call
                Pairing.new(**identities, host:, port: Integer(port))
            ensure
                socket&.close
            end

            # Pair-verify on a plain connection, then encrypt that socket.
            def self.connect(pairing)
                host   = "#{pairing.host}:#{pairing.port}"
                socket = tcp(pairing.host, pairing.port)
                plain  = HTTP.new(Transport::Plain.new(socket), host)
                keys   = PairVerify.new(plain, pairing).call
                new(HTTP.new(Transport::Secure.new(socket, **keys), host))
            rescue StandardError
                socket&.close
                raise
            end

            def self.open(pairing)
                client = connect(pairing)
                yield client
            ensure
                client&.close
            end

            def self.tcp(host, port, timeout = TIMEOUT)
                socket = Socket.tcp(host, Integer(port),
                                    connect_timeout: TIMEOUT)
                socket.timeout = timeout
                socket
            end
            private_class_method :tcp

            def initialize(http)
                @http = http
            end

            def accessories = get("/accessories").fetch("accessories")

            # ids: [aid, iid] pairs; returns the characteristics' JSON.
            def read(*ids)
                query = ids.map { it.join(".") }.join(",")
                get("/characteristics?id=#{query}").fetch("characteristics")
            end

            # values: { [aid, iid] => value }
            def write(values)
                list = values.map { |(aid, iid), value| { aid:, iid:, value: } }
                response = @http.request("PUT", "/characteristics",
                                         body: JSON.generate(
                                             characteristics: list
                                         ),
                                         type: JSON_TYPE)
                check_write(response)
            end

            # Removes a controller's pairing (ours by default).
            def remove_pairing(controller_id)
                @http.tlv("/pairings", state: 1, method: 4,
                                       identifier: controller_id)
            end

            def close = @http.close

            private

            def get(path)
                response = @http.request("GET", path)
                raise ProtocolError, "GET #{path}: HTTP #{response.status}" \
                    unless response.success?
                response.json
            end

            def check_write(response)
                return if response.status == 204
                failed = response.json.fetch("characteristics", [])
                                 .reject { it.fetch("status", 0).zero? }
                return if response.success? && failed.empty?
                raise ProtocolError, "write rejected: #{failed.to_json}"
            end
        end
    end
end

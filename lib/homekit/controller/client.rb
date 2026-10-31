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
            # timeout: seconds a connection or a reply may take.
            def self.connect(pairing, timeout: TIMEOUT)
                host   = "#{pairing.host}:#{pairing.port}"
                socket = tcp(pairing.host, pairing.port, timeout)
                plain  = HTTP.new(Transport::Plain.new(socket), host)
                keys   = PairVerify.new(plain, pairing).call
                new(HTTP.new(Transport::Secure.new(socket, **keys), host))
            rescue StandardError
                socket&.close
                raise
            end

            def self.open(pairing, timeout: TIMEOUT)
                client = connect(pairing, timeout:)
                yield client
            ensure
                client&.close
            end

            # Follows characteristics across sessions and failures: see
            # Watch.
            def self.watch(pairing, *ids, **, &)
                Watch.new(pairing, ids, **).each(&)
            end

            def self.tcp(host, port, timeout = TIMEOUT)
                socket = Socket.tcp(host, Integer(port),
                                    connect_timeout: [timeout, TIMEOUT].min)
                socket.timeout = timeout
                socket
            end
            private_class_method :tcp

            def initialize(http)
                @http = http
            end

            def accessories = list(get("/accessories"), "accessories")

            # ids: [aid, iid] pairs; returns the characteristics' JSON.
            def read(*ids)
                query = ids.map { it.join(".") }.join(",")
                list(get("/characteristics?id=#{query}"), "characteristics")
            end

            # ids: [aid, iid] pairs; returns { [aid, iid] => value }.
            def values(*ids) = by_id(read(*ids))

            # values: { [aid, iid] => value }
            def write(values)
                put(values.map { |(aid, iid), value| { aid:, iid:, value: } })
            end

            # Has the accessory send changes to these characteristics
            # ([aid, iid] pairs, "ev" among their perms) for as long as
            # this session lasts; #next_event takes them.
            def subscribe(*ids)   = notify(ids, true)
            def unsubscribe(*ids) = notify(ids, false)

            # The next change the accessory sends, { [aid, iid] => value };
            # nil when none comes within timeout seconds (nil: wait for
            # ever). EOFError when the accessory closes the session: a new
            # one must subscribe again.
            def next_event(timeout: nil)
                event = @http.next_event(timeout) or return
                by_id(list(event.json, "characteristics"))
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

            # The array under key in a JSON reply, of objects.
            def list(json, key)
                items = json.fetch(key, nil)
                return items if items.is_a?(Array) && items.all?(Hash)
                raise ProtocolError, "reply has no #{key} list"
            end

            # { [aid, iid] => value } from characteristics' JSON.
            def by_id(list)
                list.to_h { [it.values_at("aid", "iid"), it["value"]] }
            end

            def notify(ids, enable)
                put(ids.map { |aid, iid| { aid:, iid:, ev: enable } })
            end

            def put(list)
                response = @http.request("PUT", "/characteristics",
                                         body: JSON.generate(
                                             characteristics: list
                                         ),
                                         type: JSON_TYPE)
                check_write(response)
            end

            def accepted?(item)
                status = item.is_a?(Hash) && item.fetch("status", 0)
                Integer(status, exception: false)&.zero?
            end

            def check_write(response)
                return if response.status == 204
                failed = Array(response.json["characteristics"])
                         .reject { accepted?(it) }
                return if response.success? && failed.empty?
                raise ProtocolError, "write rejected: #{failed.to_json}"
            end
        end
    end
end

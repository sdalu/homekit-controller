# frozen_string_literal: true

require "json"
require "socket"
require "timeout"

require "test_helper"
require "support/fake_accessory"

# Client.watch against a fake accessory on a TCP port: each connection
# runs one script (verified, then what the accessory does), and the
# watch must ride out what the network does to it.
class WatchTest < Minitest::Test
    HAP = HomeKit::Controller
    ID  = [1, 10].freeze

    def setup
        @accessory = FakeAccessory.new
        @server    = TCPServer.new("127.0.0.1", 0)
        @pairing   = pair
        @lost      = []
    end

    def teardown
        @thread&.kill
        @server.close
    end

    def test_reconnects_and_resyncs_after_a_drop
        serve(-> { it.open(20.0).event(20.5).close },
              -> { it.open(21.0).event(21.5) })
        assert_equal [20.0, 20.5, 21.0, 21.5], watch(4)
        assert_equal [EOFError], @lost.map(&:class)
    end

    def test_a_quiet_session_is_probed
        serve(-> { it.open(20.0).probed(20.0).event(22.0) })
        assert_equal [20.0, 22.0], watch(2, idle: 0.1)
    end

    def test_an_accessory_gone_silent_is_left_for_a_new_session
        serve(-> { it.open(20.0).probed(nil) },
              -> { it.open(23.0) })
        assert_equal [20.0, 23.0], watch(2, idle: 0.1)
        assert_equal [IO::TimeoutError], @lost.map(&:class)
    end

    def test_an_unreachable_accessory_is_retried
        port = @server.addr[1]
        @server.close
        Thread.new do
            sleep 0.2
            @server = TCPServer.new("127.0.0.1", port)
            serve(-> { it.open(19.0) })
        end
        assert_equal [19.0], watch(1)
        refute_empty @lost
        assert(@lost.all?(SystemCallError))
    end

    def test_a_revoked_pairing_ends_the_watch
        serve(-> { it.open(20.0).close }, lambda(&:refuse))
        assert_raises(HAP::PairingError) { watch(3) }
    end

    def test_a_refused_subscription_ends_the_watch
        serve(lambda(&:refuse_subscription))
        assert_raises(HAP::ProtocolError) { watch(1) }
    end

    def test_the_callers_own_errors_are_not_retried
        serve(-> { it.open(20.0) })
        assert_raises(IOError) do
            Timeout.timeout(5) do
                HAP::Client.watch(@pairing, ID, **options) { raise IOError }
            end
        end
        assert_empty @lost
    end

    private

    def options(**more)
        { backoff: 0.01..0.05, timeout: 0.3, lost: ->(e) { @lost << e } }
            .merge(more)
    end

    # The first count values the watch yields for ID.
    def watch(count, **more)
        seen = []
        Timeout.timeout(5) do
            HAP::Client.watch(@pairing, ID, **options(**more)) do |values|
                seen << values.fetch(ID)
                break if seen.size == count
            end
        end
        seen
    end

    def pair
        http       = HAP::HTTP.new(LoopTransport.new(@accessory), "bridge")
        identities = HAP::PairSetup.new(http, "123-45-678").call
        HAP::Pairing.new(**identities, host: "127.0.0.1",
                                       port: @server.addr[1])
    end

    # Runs one script per connection accepted, in order.
    def serve(*scripts)
        @thread = Thread.new do
            scripts.each { it.call(Side.new(@server.accept, @accessory)) }
            sleep
        end
        @thread.report_on_exception = false
    end

    # The accessory's end of one connection.
    class Side
        def initialize(socket, accessory)
            @socket    = socket
            @accessory = accessory
            @reader    = HAP::HTTP::Reader.new(HAP::Transport::Plain.new(socket))
        end

        # Pair-verify, the subscription, then the values read.
        def open(value)
            verify
            body
            @secure.write("HTTP/1.1 204 No Content\r\n\r\n")
            answer(value)
        end

        # Reads the probe, and answers it unless value is nil.
        def probed(value)
            value.nil? ? body : answer(value)
            self
        end

        def event(value)
            @secure.write(reply(value, "EVENT/1.0"))
            self
        end

        def close = @socket.close

        # Pair-verify refused: the accessory no longer knows us.
        def refuse
            body
            pair_verify(state: 2, error: 2)
        end

        # "Notification not supported" for the characteristic.
        def refuse_subscription
            verify
            body
            json = JSON.generate(characteristics: [
                                     { aid: ID[0], iid: ID[1], status: -70_409 }
                                 ])
            @secure.write("HTTP/1.1 207 Multi-Status\r\nContent-Length: " \
                          "#{json.bytesize}\r\n\r\n#{json}")
        end

        private

        def verify
            2.times { pair_verify(@accessory.handle("/pair-verify", body)) }
            keys    = @accessory.session_keys
            @secure = HAP::Transport::Secure.new(
                @socket, write_key: keys[:read_key], read_key: keys[:write_key]
            )
            @reader = HAP::HTTP::Reader.new(@secure)
        end

        def body = @reader.message.last.body

        def pair_verify(items)
            tlv = HAP::TLV8.encode(items)
            @socket.write("HTTP/1.1 200 OK\r\nContent-Length: " \
                          "#{tlv.bytesize}\r\n\r\n#{tlv}")
        end

        def answer(value)
            body
            @secure.write(reply(value))
            self
        end

        def reply(value, version = "HTTP/1.1")
            json = JSON.generate(characteristics: [
                                     { aid: ID[0], iid: ID[1], value: }
                                 ])
            "#{version} 200 OK\r\nContent-Length: #{json.bytesize}\r\n" \
                "\r\n#{json}"
        end
    end
end

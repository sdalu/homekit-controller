# frozen_string_literal: true

require "socket"

require "test_helper"

class SessionTest < Minitest::Test
    HAP = HomeKit::Controller

    def test_secure_transport_round_trips_across_frames
        left, right = UNIXSocket.pair
        one, two = Array.new(2) { Random.bytes(32) }
        writer = HAP::Transport::Secure.new(left, write_key: one,
                                                  read_key: two)
        reader = HAP::Transport::Secure.new(right, write_key: two,
                                                   read_key: one)
        data = Random.bytes(3000)
        writer.write(data)
        assert_equal data, Array.new(3) { reader.read_chunk }.join
    end

    def test_unseal_rejects_tampered_data
        key = Random.bytes(32)
        nonce = HAP::Crypto.counter_nonce(0)
        sealed = HAP::Crypto.seal(key, nonce, "hello")
        sealed[0] = (sealed[0].ord ^ 1).chr
        assert_raises(HAP::AuthenticationError) do
            HAP::Crypto.unseal(key, nonce, sealed)
        end
    end

    def test_http_sets_events_aside_and_reads_chunked_bodies
        transport = CannedTransport.new(
            "EVENT/1.0 200 OK\r\nContent-Length: 2\r\n\r\n{}" \
            "HTTP/1.1 200 OK\r\nTransfer-Encoding: chunked\r\n\r\n" \
            "5\r\n{\"a\":\r\n2\r\n1}\r\n0\r\n\r\n"
        )
        http = HAP::HTTP.new(transport, "bridge")
        response = http.request("GET", "/accessories")
        assert_equal({ "a" => 1 }, response.json)
        assert_equal 1, http.events.size
        assert_match(%r{\AGET /accessories HTTP/1.1\r\n}, transport.sent)
    end

    # Hands out canned bytes a few at a time, to exercise buffering.
    class CannedTransport
        attr_reader :sent

        def initialize(reply)
            @reply = reply.b
            @sent  = +""
        end

        def write(data) = @sent << data
        def read_chunk  = @reply.slice!(0, 7)
        def close       = nil
    end
end

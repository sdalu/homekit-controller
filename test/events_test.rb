# frozen_string_literal: true

require "json"
require "socket"

require "test_helper"

# Subscriptions and their events over an encrypted session on a socket
# pair: the accessory's end writes its replies and events ahead, as an
# accessory would, and reads back what the controller sent.
class EventsTest < Minitest::Test
    HAP        = HomeKit::Controller
    NO_CONTENT = "HTTP/1.1 204 No Content\r\n\r\n"

    def setup
        left, right = UNIXSocket.pair
        one, two    = Array.new(2) { Random.bytes(32) }
        ours = HAP::Transport::Secure.new(left, write_key: one, read_key: two)
        @client    = HAP::Client.new(HAP::HTTP.new(ours, "bridge"))
        @accessory = HAP::Transport::Secure.new(right, write_key: two,
                                                       read_key: one)
    end

    def teardown = @client.close

    def test_subscribe_asks_for_events
        @accessory.write(NO_CONTENT)
        @client.subscribe([1, 10], [1, 11])
        assert_equal [{ "aid" => 1, "iid" => 10, "ev" => true },
                      { "aid" => 1, "iid" => 11, "ev" => true }],
                     sent.fetch("characteristics")
    end

    def test_unsubscribe_stops_them
        @accessory.write(NO_CONTENT)
        @client.unsubscribe([1, 10])
        assert_equal [{ "aid" => 1, "iid" => 10, "ev" => false }],
                     sent.fetch("characteristics")
    end

    def test_a_refused_subscription_is_reported
        refused = [{ aid: 1, iid: 10, status: -70_409 }]
        @accessory.write(reply(207, { characteristics: refused }))
        error = assert_raises(HAP::ProtocolError) do
            @client.subscribe([1, 10])
        end
        assert_match(/-70409/, error.message)
    end

    def test_an_event_gives_the_changes
        @accessory.write(event([1, 10] => 21.5, [1, 11] => 1))
        assert_equal({ [1, 10] => 21.5, [1, 11] => 1 },
                     @client.next_event(timeout: 1))
    end

    def test_no_event_within_the_timeout_gives_nil
        assert_nil @client.next_event(timeout: 0.05)
    end

    # One frame carries both: the second is already off the socket when
    # the first is taken, so the socket has nothing more to signal.
    def test_events_sent_together_are_each_given
        @accessory.write(event([1, 10] => 20.0) + event([1, 10] => 20.5))
        assert_equal({ [1, 10] => 20.0 }, @client.next_event(timeout: 1))
        assert_equal({ [1, 10] => 20.5 }, @client.next_event(timeout: 0))
    end

    def test_an_event_during_a_request_is_kept_for_later
        @accessory.write(event([1, 10] => 19.0) + NO_CONTENT)
        @client.write([1, 11] => 20.0)
        assert_equal({ [1, 10] => 19.0 }, @client.next_event(timeout: 0))
    end

    def test_a_response_to_no_request_is_refused
        @accessory.write(NO_CONTENT)
        assert_raises(HAP::ProtocolError) { @client.next_event(timeout: 1) }
    end

    def test_the_accessory_closing_ends_the_wait
        @accessory.close
        assert_raises(EOFError) { @client.next_event(timeout: 1) }
    end

    private

    def reply(status, body, version: "HTTP/1.1")
        json = JSON.generate(body)
        "#{version} #{status} OK\r\nContent-Type: application/hap+json\r\n" \
            "Content-Length: #{json.bytesize}\r\n\r\n#{json}"
    end

    def event(changes)
        list = changes.map { |(aid, iid), value| { aid:, iid:, value: } }
        reply(200, { characteristics: list }, version: "EVENT/1.0")
    end

    # The JSON body of the request the controller sent.
    def sent
        data = +"".b
        data << @accessory.read_chunk until data.include?("\r\n\r\n")
        head, body = data.split("\r\n\r\n", 2)
        length = head[/^Content-Length: (\d+)/i, 1].to_i
        body << @accessory.read_chunk while body.bytesize < length
        JSON.parse(body)
    end
end

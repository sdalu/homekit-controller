# frozen_string_literal: true

require "json"

require "test_helper"

class ClientTest < Minitest::Test
    HAP = HomeKit::Controller

    # Answers every request with one canned response.
    FakeHTTP = Struct.new(:response, :sent) do
        def request(*args, **options)
            self.sent = [args, options]
            response
        end
    end

    def write(status, body = "")
        response = HAP::HTTP::Response.new(status, {}, body)
        HAP::Client.new(FakeHTTP.new(response)).write({ [2, 15] => 30.0 })
    end

    def test_write_accepted_with_no_content
        assert_nil write(204)
    end

    def test_write_refused_for_one_characteristic
        body = JSON.generate(characteristics: [
                                 { aid: 2, iid: 15, status: -70_410 }
                             ])
        error = assert_raises(HAP::ProtocolError) { write(207, body) }
        assert_match(/-70410/, error.message)
    end

    def test_write_refused_outright
        assert_raises(HAP::ProtocolError) { write(400) }
    end
end

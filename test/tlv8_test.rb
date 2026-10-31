# frozen_string_literal: true

require "test_helper"

class TLV8Test < Minitest::Test
    TLV8 = HomeKit::Controller::TLV8

    def test_encodes_integers_as_one_byte
        assert_equal "\x06\x01\x01\x00\x01\x00".b,
                     TLV8.encode(state: 1, method: 0)
    end

    def test_round_trips_values_longer_than_255_bytes
        key   = (0..383).map { it % 256 }.pack("C*")
        bytes = TLV8.encode(public_key: key, state: 2)
        assert_equal 384 + (2 * 2) + 3, bytes.bytesize
        assert_equal({ public_key: key, state: "\x02".b }, TLV8.decode(bytes))
    end

    def test_encodes_empty_values
        assert_equal "\xff\x00".b, TLV8.encode(separator: "")
    end

    def test_rejects_truncated_input
        assert_raises(HomeKit::Controller::ProtocolError) do
            TLV8.decode("\x03\x05abc".b)
        end
    end

    def test_reports_accessory_errors
        error = assert_raises(HomeKit::Controller::PairingError) do
            TLV8.check!(TLV8.decode(TLV8.encode(state: 2, error: 6)))
        end
        assert_match(/already paired/, error.message)
    end
end

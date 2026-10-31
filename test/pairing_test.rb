# frozen_string_literal: true

require "tmpdir"

require "test_helper"
require "support/fake_accessory"

class PairingTest < Minitest::Test
    HAP = HomeKit::Controller

    def setup
        @accessory = FakeAccessory.new
        @http      = http(@accessory)
    end

    def test_pair_setup_then_verify_agree_on_keys
        pairing = pair("12345678")
        assert_equal @accessory.public_key, pairing.accessory_key
        assert_equal pairing.controller_id, @accessory.controller_id
        keys = HAP::PairVerify.new(@http, pairing).call
        assert_equal @accessory.session_keys, keys
    end

    def test_wrong_setup_code_is_reported
        error = assert_raises(HAP::PairingError) { pair("87654321") }
        assert_match(/wrong setup code/, error.message)
    end

    def test_pairing_survives_a_save_and_load
        pairing = pair("123-45-678")
        Dir.mktmpdir do |dir|
            path = File.join(dir, "homekit", "pairing.json")
            pairing.save(path)
            assert_equal 0o600, File.stat(path).mode & 0o777
            assert_equal pairing, HAP::Pairing.load(path)
        end
    end

    def test_load_rejects_damaged_file_without_echoing_it
        saved = JSON.pretty_generate(pair("12345678").to_json_hash)
        Dir.mktmpdir do |dir|
            path = File.join(dir, "pairing.json")
            ["{}", saved[0, 100], saved[0, 200], "[]"].each do |content|
                File.write(path, content)
                error = assert_raises(HAP::Error) { HAP::Pairing.load(path) }
                refute_includes error.message, "controller"
            end
        end
    end

    def test_verify_refuses_an_accessory_with_another_key
        pairing = pair("12345678")
        impostor = FakeAccessory.new(id: @accessory.id)
        error = assert_raises(HAP::AuthenticationError) do
            HAP::PairVerify.new(http(impostor), pairing).call
        end
        assert_match(/signature/, error.message)
    end

    def test_verify_refuses_an_accessory_with_another_id
        pairing = pair("12345678")
        other = FakeAccessory.new(id: "11:22:33:44:55:66", key: @accessory.key)
        error = assert_raises(HAP::AuthenticationError) do
            HAP::PairVerify.new(http(other), pairing).call
        end
        assert_match(/unexpected accessory/, error.message)
    end

    # Before pair-verify authenticates anything: whatever answers at the
    # accessory's address may send it.
    def test_verify_refuses_a_malformed_key
        pairing = pair("12345678")
        reply   = { public_key: "short", encrypted_data: Random.bytes(40) }
        http    = Object.new
        http.define_singleton_method(:tlv) { |*, **| reply }
        error = assert_raises(HAP::AuthenticationError) do
            HAP::PairVerify.new(http, pairing).call
        end
        assert_match(/malformed X25519 key/, error.message)
    end

    def test_setup_refuses_a_wrong_srp_proof
        @http = http(FakeAccessory.new(tamper: :proof))
        error = assert_raises(HAP::AuthenticationError) { pair("12345678") }
        assert_match(/SRP proof/, error.message)
    end

    def test_setup_refuses_a_forged_accessory_identity
        @http = http(FakeAccessory.new(tamper: :signature))
        error = assert_raises(HAP::AuthenticationError) { pair("12345678") }
        assert_match(/signature/, error.message)
    end

    def test_setup_code_must_have_eight_digits
        assert_raises(ArgumentError) { pair("1234567") }
    end

    private

    def http(accessory) = HAP::HTTP.new(LoopTransport.new(accessory), "bridge")

    def pair(code)
        identities = HAP::PairSetup.new(@http, code).call
        HAP::Pairing.new(**identities, host: "bridge", port: 80)
    end
end

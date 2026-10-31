# frozen_string_literal: true

require "test_helper"

class SRPTest < Minitest::Test
    VECTORS = File.readlines(File.expand_path("support/srp_vectors.txt",
                                              __dir__), chomp: true)
                  .grep_v(/\A#/)
                  .to_h { it.split("=", 2) }
                  .transform_values { [it].pack("H*") }

    def setup
        @srp = HomeKit::Controller::SRP.new("password123",
                                            username: "alice",
                                            secret: VECTORS["a"])
        @srp.compute(VECTORS["s"], VECTORS["B"])
    end

    def test_public_key_matches_vector
        assert_equal VECTORS["A"], @srp.public_key
    end

    def test_session_key_matches_vector
        assert_equal VECTORS["K"], @srp.session_key
    end

    def test_proof_matches_vector
        assert_equal VECTORS["M1"], @srp.proof
    end

    def test_rejects_wrong_server_proof
        refute @srp.verify?("\0".b * 64)
        refute @srp.verify?("short")
    end
end

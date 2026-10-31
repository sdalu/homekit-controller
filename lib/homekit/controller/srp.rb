# frozen_string_literal: true

require "openssl"
require "securerandom"

module HomeKit
    module Controller
        # SRP-6a client as profiled by HAP: the 3072-bit group of RFC 5054
        # with SHA-512, every public value padded to the modulus length.
        class SRP
            N = OpenSSL::BN.new(<<~HEX.delete("\n "), 16)
                FFFFFFFF FFFFFFFF C90FDAA2 2168C234 C4C6628B 80DC1CD1
                29024E08 8A67CC74 020BBEA6 3B139B22 514A0879 8E3404DD
                EF9519B3 CD3A431B 302B0A6D F25F1437 4FE1356D 6D51C245
                E485B576 625E7EC6 F44C42E9 A637ED6B 0BFF5CB6 F406B7ED
                EE386BFB 5A899FA5 AE9F2411 7C4B1FE6 49286651 ECE45B3D
                C2007CB8 A163BF05 98DA4836 1C55D39A 69163FA8 FD24CF5F
                83655D23 DCA3AD96 1C62F356 208552BB 9ED52907 7096966D
                670C354E 4ABC9804 F1746C08 CA18217C 32905E46 2E36CE3B
                E39E772C 180E8603 9B2783A2 EC07A28F B5C55DF0 6F4C52C9
                DE2BCBF6 95581718 3995497C EA956AE5 15D22618 98FA0510
                15728E5A 8AAAC42D AD33170D 04507A33 A85521AB DF1CBA64
                ECFB8504 58DBEF0A 8AEA7157 5D060C7D B3970F85 A6E1E4C7
                ABF5AE8C DB0933D7 1E8C94E0 4A25619D CEE3D226 1AD2EE6B
                F12FFA06 D98A0864 D8760273 3EC86A64 521F2B18 177B200C
                BBE11757 7A615D6C 770988C0 BAD946E2 08E24FA0 74E5AB31
                43DB5BFC E0FD108E 4B82D120 A93AD2CA FFFFFFFF FFFFFFFF
            HEX
            G      = OpenSSL::BN.new(5)
            LENGTH = 384

            attr_reader :public_key, :session_key, :proof

            def initialize(password, username: "Pair-Setup",
                           secret: SecureRandom.random_bytes(32))
                @username   = username
                @password   = password
                @secret     = OpenSSL::BN.new(secret, 2)
                @public_key = pad(G.mod_exp(@secret, N))
            end

            # Takes the accessory's salt and public key, returns proof M1.
            def compute(salt, server_key)
                b = OpenSSL::BN.new(server_key, 2)
                raise AuthenticationError, "invalid SRP public key" if
                    (b % N).zero?
                @session_key = digest(pad(shared_secret(salt, b)))
                @proof       = client_proof(salt, server_key)
            end

            # Checks the accessory's proof M2.
            def verify?(server_proof)
                expected = digest(@public_key, @proof, @session_key)
                server_proof.bytesize == expected.bytesize &&
                    OpenSSL.fixed_length_secure_compare(expected, server_proof)
            end

            private

            def shared_secret(salt, b)
                x    = int(digest(salt, digest("#{@username}:#{@password}")))
                k    = int(digest(pad(N), pad(G)))
                u    = int(digest(@public_key, pad(b)))
                base = b.mod_sub(k.mod_mul(G.mod_exp(x, N), N), N)
                base.mod_exp(@secret + (u * x), N)
            end

            def client_proof(salt, server_key)
                group = digest(N.to_s(2)).bytes
                                         .zip(digest(G.to_s(2)).bytes)
                                         .map { |n, g| n ^ g }.pack("C*")
                digest(group, digest(@username), salt,
                       @public_key, pad(server_key), @session_key)
            end

            def digest(*parts) = OpenSSL::Digest::SHA512.digest(parts.join.b)
            def int(bytes)     = OpenSSL::BN.new(bytes, 2)

            def pad(value)
                bytes = value.is_a?(String) ? value.b : value.to_s(2)
                ("\0" * (LENGTH - bytes.bytesize)).b + bytes
            end
        end
    end
end

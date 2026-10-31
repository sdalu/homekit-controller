# frozen_string_literal: true

require "openssl"

module HomeKit
    module Controller
        # Pair-verify (messages M1 to M4): an X25519 exchange in which each
        # side signs both ephemeral keys with its long-term key. Yields the
        # keys for the encrypted session.
        class PairVerify
            PATH = "/pair-verify"

            def initialize(http, pairing)
                @http      = http
                @pairing   = pairing
                @ephemeral = OpenSSL::PKey.generate_key("X25519")
            end

            # Returns { write_key:, read_key: } for Transport::Secure.
            def call
                m2 = @http.tlv(PATH, state: 1, public_key: ours)
                theirs, sealed = TLV8.fetch_all(m2, :public_key,
                                                :encrypted_data)
                shared  = derive(theirs)
                session = Crypto.hkdf(shared, "Pair-Verify-Encrypt-Salt",
                                      "Pair-Verify-Encrypt-Info")
                check_accessory(session, theirs, sealed)
                prove_controller(session, theirs)
                session_keys(shared)
            end

            private

            def ours = @ephemeral.raw_public_key

            def derive(theirs)
                @ephemeral.derive(
                    OpenSSL::PKey.new_raw_public_key("X25519", theirs)
                )
            end

            def check_accessory(session, theirs, sealed)
                plain = Crypto.unseal(session,
                                      Crypto.label_nonce("PV-Msg02"), sealed)
                id, signature = TLV8.fetch_all(TLV8.decode(plain),
                                               :identifier, :signature)
                raise AuthenticationError, "unexpected accessory #{id}" unless
                    id == @pairing.accessory_id.b
                Crypto.verify!(@pairing.accessory_key, signature,
                               theirs + id + ours)
            end

            def prove_controller(session, theirs)
                id        = @pairing.controller_id
                signature = @pairing.signing_key.sign(nil, ours + id + theirs)
                plain     = TLV8.encode(identifier: id, signature:)
                sealed    = Crypto.seal(session,
                                        Crypto.label_nonce("PV-Msg03"), plain)
                @http.tlv(PATH, state: 3, encrypted_data: sealed)
            end

            def session_keys(shared)
                { write_key: Crypto.hkdf(shared, "Control-Salt",
                                         "Control-Write-Encryption-Key"),
                  read_key: Crypto.hkdf(shared, "Control-Salt",
                                        "Control-Read-Encryption-Key") }
            end
        end
    end
end

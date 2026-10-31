# frozen_string_literal: true

require "openssl"
require "securerandom"

module HomeKit
    module Controller
        # Pair-setup (messages M1 to M6): proves knowledge of the setup
        # code through SRP, then swaps long-term Ed25519 public keys over
        # the channel the SRP session key protects.
        class PairSetup
            PATH = "/pair-setup"

            def initialize(http, setup_code)
                @http          = http
                @code          = self.class.normalise(setup_code)
                @controller_id = SecureRandom.uuid.upcase
                @key           = OpenSSL::PKey.generate_key("ED25519")
            end

            # "12345678" or "123-45-678" both give "123-45-678".
            def self.normalise(code)
                digits = code.to_s.delete("^0-9")
                raise ArgumentError, "setup code must have 8 digits" unless
                    digits.size == 8
                "#{digits[0, 3]}-#{digits[3, 2]}-#{digits[5, 3]}"
            end

            # Returns the identities for a Pairing (host and port aside).
            def call
                srp = exchange_keys
                accessory = exchange_identities(srp.session_key)
                { controller_id: @controller_id,
                  controller_key: @key.raw_private_key, **accessory }
            end

            private

            def exchange_keys
                m2 = @http.tlv(PATH, state: 1, method: 0)
                salt, server_key = TLV8.fetch_all(m2, :salt, :public_key)
                srp   = SRP.new(@code)
                proof = srp.compute(salt, server_key)
                m4 = @http.tlv(PATH, state: 3, public_key: srp.public_key,
                                     proof:)
                return srp if srp.verify?(TLV8.fetch_all(m4, :proof).first)
                raise AuthenticationError, "accessory failed the SRP proof"
            end

            def exchange_identities(srp_key)
                session = Crypto.hkdf(srp_key, "Pair-Setup-Encrypt-Salt",
                                      "Pair-Setup-Encrypt-Info")
                m6 = @http.tlv(PATH, state: 5,
                                     encrypted_data: m5(srp_key, session))
                sealed = TLV8.fetch_all(m6, :encrypted_data).first
                plain  = Crypto.unseal(session,
                                       Crypto.label_nonce("PS-Msg06"), sealed)
                accessory(srp_key, TLV8.decode(plain))
            end

            def m5(srp_key, session)
                x = Crypto.hkdf(srp_key, "Pair-Setup-Controller-Sign-Salt",
                                "Pair-Setup-Controller-Sign-Info")
                public_key = @key.raw_public_key
                signature  = @key.sign(nil, x + @controller_id + public_key)
                plain = TLV8.encode(identifier: @controller_id, public_key:,
                                    signature:)
                Crypto.seal(session, Crypto.label_nonce("PS-Msg05"), plain)
            end

            def accessory(srp_key, items)
                id, key, signature =
                    TLV8.fetch_all(items, :identifier, :public_key, :signature)
                x = Crypto.hkdf(srp_key, "Pair-Setup-Accessory-Sign-Salt",
                                "Pair-Setup-Accessory-Sign-Info")
                Crypto.verify!(key, signature, x + id + key)
                { accessory_id: id.dup.force_encoding(Encoding::UTF_8),
                  accessory_key: key }
            end
        end
    end
end

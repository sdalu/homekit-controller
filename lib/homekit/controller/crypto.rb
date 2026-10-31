# frozen_string_literal: true

require "openssl"

module HomeKit
    module Controller
        # The primitives HAP builds on: HKDF-SHA-512, ChaCha20-Poly1305
        # and Ed25519 signatures.
        module Crypto
            TAG = 16

            module_function

            def hkdf(key, salt, info)
                OpenSSL::KDF.hkdf(key, salt:, info:, length: 32,
                                       hash: "SHA512")
            end

            # Pairing messages use a fixed label ("PS-Msg05") as nonce.
            def label_nonce(label) = ("\0" * 4).b + label.b

            # Session frames use a little-endian 64-bit counter.
            def counter_nonce(count) = [0, count].pack("VQ<")

            def seal(key, nonce, plain, aad = "")
                cipher = aead(:encrypt, key, nonce, aad)
                cipher.update(plain) + cipher.final + cipher.auth_tag
            end

            def unseal(key, nonce, sealed, aad = "")
                raise AuthenticationError, "sealed data too short" if
                    sealed.bytesize <= TAG
                tag    = sealed.byteslice(-TAG, TAG)
                cipher = aead(:decrypt, key, nonce, aad, tag)
                cipher.update(sealed.byteslice(0...-TAG)) + cipher.final
            rescue OpenSSL::Cipher::CipherError
                raise AuthenticationError, "decryption failed"
            end

            def verify!(public_key, signature, data)
                key = OpenSSL::PKey.new_raw_public_key("ED25519", public_key)
                return if key.verify(nil, signature, data)
                raise AuthenticationError, "bad Ed25519 signature"
            rescue OpenSSL::PKey::PKeyError
                raise AuthenticationError, "malformed Ed25519 key"
            end

            def aead(mode, key, nonce, aad, tag = nil)
                cipher = OpenSSL::Cipher.new("chacha20-poly1305")
                cipher.public_send(mode)
                cipher.key      = key
                cipher.iv       = nonce
                cipher.auth_tag = tag if tag
                cipher.auth_data = aad
                cipher
            end
        end
    end
end

# frozen_string_literal: true

require "openssl"
require "securerandom"

# Big-number helpers shared by the SRP steps below.
module SRPMath
    def digest(*parts) = OpenSSL::Digest::SHA512.digest(parts.join.b)
    def int(bytes)     = OpenSSL::BN.new(bytes, 2)

    def pad(value)
        bytes = value.is_a?(String) ? value.b : value.to_s(2)
        ("\0" * (384 - bytes.bytesize)).b + bytes
    end
end

# The accessory's half of pair-verify: an X25519 exchange signed with its
# long-term key, checked against the controller's from pair-setup.
module FakeVerify
    Crypto = HomeKit::Controller::Crypto
    TLV8   = HomeKit::Controller::TLV8

    private

    def pair_verify_m1(items)
        @ours, @theirs = verify_exchange(items[:public_key])
        sub = TLV8.encode(identifier: @id,
                          signature: @key.sign(nil, @ours + @id + @theirs))
        { state: 2, public_key: @ours, encrypted_data: Crypto.seal(
            @verify, Crypto.label_nonce("PV-Msg02"), sub
        ) }
    end

    def verify_exchange(theirs)
        ephemeral = OpenSSL::PKey.generate_key("X25519")
        @shared   = ephemeral.derive(
            OpenSSL::PKey.new_raw_public_key("X25519", theirs)
        )
        @verify = Crypto.hkdf(@shared, "Pair-Verify-Encrypt-Salt",
                              "Pair-Verify-Encrypt-Info")
        [ephemeral.raw_public_key, theirs]
    end

    def pair_verify_m3(items)
        sub = TLV8.decode(Crypto.unseal(@verify,
                                        Crypto.label_nonce("PV-Msg03"),
                                        items[:encrypted_data]))
        Crypto.verify!(@controller_key, sub[:signature],
                       @theirs + sub[:identifier] + @ours)
        @session_keys = %w[Write Read].to_h { session_key(it) }
        { state: 4 }
    end

    def session_key(direction)
        key = Crypto.hkdf(@shared, "Control-Salt",
                          "Control-#{direction}-Encryption-Key")
        [:"#{direction.downcase}_key", key]
    end
end

# Accessory side of pair-setup and pair-verify, written from the HAP
# specification, to run the controller code end to end. tamper: :proof
# sends a wrong SRP proof at M4, :signature a forged identity at M6.
class FakeAccessory
    include SRPMath
    include FakeVerify

    TLV8   = HomeKit::Controller::TLV8
    Crypto = HomeKit::Controller::Crypto
    N      = HomeKit::Controller::SRP::N
    G      = HomeKit::Controller::SRP::G

    attr_reader :id, :key, :controller_id, :session_keys

    def initialize(code: "123-45-678", id: "AA:BB:CC:DD:EE:FF",
                   key: OpenSSL::PKey.generate_key("ED25519"), tamper: nil)
        @code   = code
        @id     = id
        @key    = key
        @tamper = tamper
    end

    def public_key = @key.raw_public_key

    # Returns the TLV items answering a POST to a pairing endpoint.
    def handle(path, body)
        items = TLV8.decode(body)
        step  = "#{path.delete_prefix("/").tr("-", "_")}_" \
                "m#{items[:state].ord}"
        send(step, items)
    end

    private

    def pair_setup_m1(_items)
        @salt   = SecureRandom.random_bytes(16)
        x       = int(digest(@salt, digest("Pair-Setup:#{@code}")))
        @v      = G.mod_exp(x, N)
        @b      = int(SecureRandom.random_bytes(32))
        k       = int(digest(pad(N), pad(G)))
        @server = pad(k.mod_mul(@v, N).mod_add(G.mod_exp(@b, N), N))
        { state: 2, salt: @salt, public_key: @server }
    end

    def pair_setup_m3(items)
        client = pad(items[:public_key])
        u      = int(digest(client, @server))
        shared = int(client).mod_mul(@v.mod_exp(u, N), N).mod_exp(@b, N)
        @srp   = digest(pad(shared))
        return { state: 4, error: 2 } unless
            items[:proof] == client_proof(client)
        proof = digest(client, items[:proof], @srp)
        proof = proof.reverse if @tamper == :proof
        { state: 4, proof: }
    end

    def client_proof(client)
        group = digest(N.to_s(2)).bytes.zip(digest(G.to_s(2)).bytes)
                                 .map { |n, g| n ^ g }.pack("C*")
        digest(group, digest("Pair-Setup"), @salt, client, @server, @srp)
    end

    def pair_setup_m5(items)
        key  = Crypto.hkdf(@srp, "Pair-Setup-Encrypt-Salt",
                           "Pair-Setup-Encrypt-Info")
        sub  = TLV8.decode(Crypto.unseal(key, Crypto.label_nonce("PS-Msg05"),
                                         items[:encrypted_data]))
        check_controller(sub)
        { state: 6, encrypted_data: Crypto.seal(
            key, Crypto.label_nonce("PS-Msg06"), accessory_identity
        ) }
    end

    def check_controller(sub)
        x = Crypto.hkdf(@srp, "Pair-Setup-Controller-Sign-Salt",
                        "Pair-Setup-Controller-Sign-Info")
        @controller_id  = sub[:identifier]
        @controller_key = sub[:public_key]
        Crypto.verify!(@controller_key, sub[:signature],
                       x + @controller_id + @controller_key)
    end

    def accessory_identity
        x = Crypto.hkdf(@srp, "Pair-Setup-Accessory-Sign-Salt",
                        "Pair-Setup-Accessory-Sign-Info")
        signature = @key.sign(nil, x + @id + public_key)
        signature = signature.reverse if @tamper == :signature
        TLV8.encode(identifier: @id, public_key:, signature:)
    end
end

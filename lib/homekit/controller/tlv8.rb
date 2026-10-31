# frozen_string_literal: true

module HomeKit
    module Controller
        # Type-length-value encoding used by the pairing endpoints. Values
        # longer than 255 bytes are split into consecutive items of the
        # same type, and joined back on decoding.
        module TLV8
            TYPES = {
                method: 0x00, identifier: 0x01, salt: 0x02,
                public_key: 0x03, proof: 0x04, encrypted_data: 0x05,
                state: 0x06, error: 0x07, retry_delay: 0x08,
                certificate: 0x09, signature: 0x0a, permissions: 0x0b,
                fragment_data: 0x0c, fragment_last: 0x0d, flags: 0x13,
                separator: 0xff
            }.freeze
            NAMES = TYPES.invert.freeze

            ERRORS = {
                1 => "unknown error",
                2 => "authentication failed (wrong setup code?)",
                3 => "too many attempts, retry later",
                4 => "accessory cannot accept more pairings",
                5 => "too many failed attempts, accessory must be reset",
                6 => "accessory is already paired " \
                     "(remove it from Apple Home first)",
                7 => "accessory is busy pairing with another controller"
            }.freeze

            module_function

            def encode(items)
                items.map { |name, value| item(TYPES.fetch(name), value) }
                     .join.b
            end

            def decode(bytes)
                items = {}
                each_item(bytes) do |type, value|
                    name = NAMES.fetch(type, type)
                    items[name] = items.fetch(name, "".b) + value
                end
                items
            end

            # Raises PairingError if the accessory reported an error.
            def check!(items)
                code = items[:error]&.ord
                return items unless code
                raise PairingError, ERRORS.fetch(code, "error #{code}")
            end

            def fetch_all(items, *names)
                names.map do |name|
                    items.fetch(name) do
                        raise ProtocolError, "missing TLV item #{name}"
                    end
                end
            end

            def item(type, value)
                value = [value].pack("C") if value.is_a?(Integer)
                value = value.b
                (0...[value.bytesize, 1].max).step(255).map do |offset|
                    chunk = value.byteslice(offset, 255)
                    [type, chunk.bytesize].pack("CC") + chunk
                end
            end

            def each_item(bytes)
                pos = 0
                while pos < bytes.bytesize
                    type, length = bytes.byteslice(pos, 2).unpack("CC")
                    value = bytes.byteslice(pos + 2, length.to_i).to_s
                    raise ProtocolError, "truncated TLV" if
                        value.bytesize != length
                    yield type, value
                    pos += 2 + length
                end
            end
        end
    end
end

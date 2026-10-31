# frozen_string_literal: true

module HomeKit
    module Controller
        # Byte pipes the HTTP layer runs over: the socket as is during
        # pairing, then encrypted frames once a session is verified.
        module Transport
            class Plain
                def initialize(socket)
                    @socket = socket
                end

                def write(data) = @socket.write(data)
                def read_chunk  = @socket.readpartial(4096)
                def close       = @socket.close
            end

            # Frames of at most 1024 bytes: a little-endian length, used
            # as additional data, then the ciphertext and its tag.
            class Secure
                FRAME = 1024

                def initialize(socket, write_key:, read_key:)
                    @socket = socket
                    @keys   = { write: write_key, read: read_key }
                    @counts = { write: 0, read: 0 }
                end

                def write(data)
                    (0...data.bytesize).step(FRAME) do |offset|
                        @socket.write(seal(data.byteslice(offset, FRAME)))
                    end
                end

                def read_chunk
                    aad    = read_exact(2)
                    sealed = read_exact(aad.unpack1("v") + Crypto::TAG)
                    Crypto.unseal(@keys[:read], nonce(:read), sealed, aad)
                end

                def close = @socket.close

                private

                def seal(chunk)
                    aad = [chunk.bytesize].pack("v")
                    aad + Crypto.seal(@keys[:write], nonce(:write), chunk, aad)
                end

                def nonce(direction)
                    Crypto.counter_nonce(@counts[direction])
                ensure
                    @counts[direction] += 1
                end

                def read_exact(count)
                    data = @socket.read(count)
                    raise EOFError, "accessory closed the connection" if
                        data.nil? || data.bytesize < count
                    data
                end
            end
        end
    end
end

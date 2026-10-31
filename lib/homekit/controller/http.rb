# frozen_string_literal: true

require "json"

module HomeKit
    module Controller
        # Just enough HTTP/1.1 for HAP: one request at a time, bodies by
        # length or chunked, and unsolicited "EVENT/1.0" notifications set
        # aside in #events until #next_event takes them.
        class HTTP
            Response = Data.define(:status, :headers, :body) do
                def success? = status.between?(200, 299)

                # The body's JSON object; ProtocolError for anything else.
                def json
                    return {} if body.empty?
                    object = JSON.parse(body)
                    return object if object.is_a?(Hash)
                    raise ProtocolError, "JSON body is not an object"
                rescue JSON::ParserError
                    raise ProtocolError, "malformed JSON body"
                end
            end

            # Reads messages off a transport, holding what arrived beyond
            # the current one. Lengths are taken only as HTTP writes them,
            # and bounded: a line, and a body (a large bridge's
            # /accessories is a few hundred KB).
            class Reader
                MAX_LINE = 8 * 1024
                MAX_BODY = 16 * 1024 * 1024

                def initialize(transport)
                    @transport = transport
                    @buffer    = "".b
                end

                # Whether part of a message has already arrived.
                def pending? = !@buffer.empty?

                # [version, Response]
                def message
                    version, status = line.split(" ", 3)
                    headers = self.headers
                    [version.to_s,
                     Response.new(status.to_i, headers, body(headers))]
                end

                private

                def headers
                    headers = {}
                    while (line = self.line) != ""
                        name, value = line.split(":", 2)
                        headers[name.strip.downcase] = value.to_s.strip
                    end
                    headers
                end

                def body(headers)
                    chunked = headers["transfer-encoding"]&.casecmp?("chunked")
                    return chunked_body if chunked
                    length = headers.fetch("content-length", "0")
                    bytes(length_of(length[/\A\d+\z/]&.to_i, length))
                end

                # Chunk sizes are hexadecimal, maybe with a ";extension".
                def chunked_body
                    body = "".b
                    while (size = chunk_size).positive?
                        body << bytes(size)
                        length_of(body.bytesize, "chunked body")
                        line
                    end
                    nil while line != ""
                    body
                end

                def chunk_size
                    text = line
                    length_of(text[/\A\h+(?=;|\z)/]&.hex, text)
                end

                # A length read from given (nil when malformed), within
                # MAX_BODY.
                def length_of(length, given)
                    raise ProtocolError, "bad length #{given[0, 20].inspect}" \
                        unless length
                    raise ProtocolError, "body too large" if length > MAX_BODY
                    length
                end

                def line
                    until (index = @buffer.index("\r\n"))
                        raise ProtocolError, "line too long" if
                            @buffer.bytesize > MAX_LINE
                        fill
                    end
                    @buffer.slice!(0, index + 2).chomp
                end

                def bytes(count)
                    fill while @buffer.bytesize < count
                    @buffer.slice!(0, count)
                end

                def fill = @buffer << @transport.read_chunk.b
            end

            TLV_TYPE = "application/pairing+tlv8"

            attr_reader :events

            def initialize(transport, host)
                @transport = transport
                @host      = host
                @reader    = Reader.new(transport)
                @events    = []
            end

            def request(method, path, body: nil, type: nil)
                exchange do
                    @transport.write(build(method, path, body, type))
                    loop do
                        version, response = @reader.message
                        return response unless version.start_with?("EVENT/")
                        @events << response
                    end
                end
            end

            # POSTs TLV items to a pairing endpoint, returns the reply's.
            def tlv(path, **items)
                response = request("POST", path, body: TLV8.encode(items),
                                                 type: TLV_TYPE)
                reply = TLV8.check!(TLV8.decode(response.body))
                return reply if response.success?
                raise ProtocolError, "#{path}: HTTP #{response.status}"
            end

            # The next EVENT/1.0 notification: the oldest set aside during
            # a request, else the next to arrive; nil when none begins
            # within timeout seconds (nil: wait for ever). Only the start
            # is waited for, so a timeout never cuts a message in two.
            def next_event(timeout = nil)
                return @events.shift unless @events.empty?
                return unless @reader.pending? ||
                              @transport.wait_readable(timeout)
                version, response = exchange { @reader.message }
                return response if version.start_with?("EVENT/")
                raise ProtocolError,
                      "HTTP #{response.status} answering no request"
            end

            def close = @transport.close

            private

            # Whatever cuts an exchange short (a timeout, a bad message, an
            # interrupt) leaves the stream between two messages, where a
            # late reply would answer the next request: the session is
            # closed instead, so that using it again raises IOError. Any
            # exception: Timeout.timeout's and Interrupt are not
            # StandardError. (A flag set after yield would close on a
            # return from the block too.)
            def exchange
                yield
            rescue Exception # rubocop:disable Lint/RescueException
                close
                raise
            end

            def build(method, path, body, type)
                head = ["#{method} #{path} HTTP/1.1", "Host: #{@host}"]
                if body
                    head += ["Content-Type: #{type}",
                             "Content-Length: #{body.bytesize}"]
                end
                "#{head.join("\r\n")}\r\n\r\n".b + body.to_s.b
            end
        end
    end
end

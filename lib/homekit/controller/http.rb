# frozen_string_literal: true

require "json"

module HomeKit
    module Controller
        # Just enough HTTP/1.1 for HAP: one request at a time, bodies by
        # length or chunked, and unsolicited "EVENT/1.0" notifications set
        # aside in #events.
        class HTTP
            Response = Data.define(:status, :headers, :body) do
                def success? = status.between?(200, 299)
                def json     = body.empty? ? {} : JSON.parse(body)
            end

            TLV_TYPE = "application/pairing+tlv8"

            attr_reader :events

            def initialize(transport, host)
                @transport = transport
                @host      = host
                @buffer    = "".b
                @events    = []
            end

            def request(method, path, body: nil, type: nil)
                @transport.write(build(method, path, body, type))
                loop do
                    version, response = read_message
                    return response unless version.start_with?("EVENT/")
                    @events << response
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

            def close = @transport.close

            private

            def build(method, path, body, type)
                head = ["#{method} #{path} HTTP/1.1", "Host: #{@host}"]
                if body
                    head += ["Content-Type: #{type}",
                             "Content-Length: #{body.bytesize}"]
                end
                "#{head.join("\r\n")}\r\n\r\n".b + body.to_s.b
            end

            def read_message
                version, status = read_line.split(" ", 3)
                headers = read_headers
                [version.to_s,
                 Response.new(status.to_i, headers, read_body(headers))]
            end

            def read_headers
                headers = {}
                while (line = read_line) != ""
                    name, value = line.split(":", 2)
                    headers[name.strip.downcase] = value.to_s.strip
                end
                headers
            end

            def read_body(headers)
                chunked = headers["transfer-encoding"]&.casecmp?("chunked")
                return read_chunked if chunked
                read_bytes(headers.fetch("content-length", "0").to_i)
            end

            def read_chunked
                body = "".b
                while (size = read_line.to_i(16)).positive?
                    body << read_bytes(size)
                    read_line
                end
                nil while read_line != ""
                body
            end

            def read_line
                fill until (index = @buffer.index("\r\n"))
                @buffer.slice!(0, index + 2).chomp
            end

            def read_bytes(count)
                fill while @buffer.bytesize < count
                @buffer.slice!(0, count)
            end

            def fill = @buffer << @transport.read_chunk.b
        end
    end
end

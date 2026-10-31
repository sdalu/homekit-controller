# frozen_string_literal: true

require "ipaddr"
require "resolv"
require "socket"

module HomeKit
    module Controller
        # Finds HAP accessories with a one-shot mDNS query for _hap._tcp.
        # It listens on the mDNS group itself rather than asking for unicast
        # replies (RFC 6762, section 6.7): a stateful firewall drops those,
        # as they come from the accessory, not from the group queried.
        class Discovery
            Service = Data.define(:name, :host, :port, :id, :model, :flags) do
                # Bit 0 of the "sf" TXT flag is set while unpaired.
                def paired? = flags.nobits?(1)
            end

            GROUP   = "224.0.0.251"
            PORT    = 5353
            SERVICE = "_hap._tcp.local"
            IN      = Resolv::DNS::Resource::IN

            # mDNS sets the top bit of a record's class ("cache flush"),
            # which Resolv decodes as an unknown, opaque type. Teach it to
            # read those as the IN records they are.
            [IN::A, IN::SRV, IN::TXT, IN::PTR].each do |type|
                key = [type::TypeValue, IN::ClassValue | 0x8000]
                Resolv::DNS::Resource::ClassHash[key] = type
            end

            # interface: address of the interface to join the group on;
            # the default lets the routing table choose.
            def self.browse(timeout: 2, interface: "0.0.0.0")
                new(interface).browse(timeout)
            end

            def initialize(interface)
                @interface = interface
                @records   = Hash.new { |hash, name| hash[name] = [] }
            end

            def browse(timeout)
                socket = listener
                socket.send(query, 0, GROUP, PORT)
                collect(socket, now + timeout)
                lookup(SERVICE, IN::PTR).map { it.name.to_s }.uniq
                                        .filter_map { service(it) }
            ensure
                socket&.close
            end

            private

            # Shares port 5353 with any mDNS daemon already running.
            def listener
                socket = UDPSocket.new
                socket.setsockopt(:SOCKET, :REUSEADDR, true)
                socket.setsockopt(:SOCKET, :REUSEPORT, true)
                socket.bind("0.0.0.0", PORT)
                group = IPAddr.new(GROUP).hton + IPAddr.new(@interface).hton
                socket.setsockopt(:IPPROTO_IP, :IP_ADD_MEMBERSHIP, group)
                socket
            end

            def query
                message = Resolv::DNS::Message.new(0)
                message.add_question(SERVICE, IN::PTR)
                message.encode
            end

            def collect(socket, deadline)
                loop do
                    left = deadline - now
                    break unless left.positive? && socket.wait_readable(left)
                    record(socket.recvfrom(9000).first)
                end
            end

            def record(packet)
                Resolv::DNS::Message.decode(packet).each_resource do
                    |name, _ttl, data|
                    @records[name.to_s.downcase] << data
                end
            rescue Resolv::DNS::DecodeError
                nil
            end

            def now = Process.clock_gettime(Process::CLOCK_MONOTONIC)

            def lookup(name, type)
                @records[name.downcase].grep(type)
            end

            def service(instance)
                srv = lookup(instance, IN::SRV).first or return
                txt = txt(instance)
                Service.new(name: instance.delete_suffix(".#{SERVICE}"),
                            host: address(srv.target), port: srv.port,
                            id: txt["id"], model: txt["md"],
                            flags: txt["sf"].to_i)
            end

            def txt(instance)
                strings = lookup(instance, IN::TXT).first&.strings.to_a
                strings.to_h { it.split("=", 2).values_at(0, 1) }
            end

            # The A record comes with the answer; else keep the name.
            def address(target)
                (lookup(target.to_s, IN::A).first&.address || target).to_s
            end
        end
    end
end

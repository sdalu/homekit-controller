# frozen_string_literal: true

require "test_helper"

# Discovery's decoding of an mDNS answer, without a network: the
# records an accessory sends, with the cache-flush bit mDNS sets on
# their class. And the socket it queries on, set up but sending nothing.
class DiscoveryTest < Minitest::Test
    Discovery = HomeKit::Controller::Discovery
    IN        = Resolv::DNS::Resource::IN
    SERVICE   = Discovery::SERVICE
    INSTANCE  = "Bridge 1.#{SERVICE}".freeze

    def test_a_cache_flush_answer_gives_the_service
        found = decode(answer)
        assert_equal ["Bridge 1", "192.0.2.7", 51_826, "AA:BB", "BR01", 1],
                     found.to_h.values
        refute_predicate found, :paired?
    end

    def test_an_answer_without_its_srv_gives_nothing
        assert_nil decode(answer(srv: false))
    end

    def test_a_utf8_instance_name_comes_back_utf8
        found = decode(answer(instance: "Thermostat S\u00e9jour.#{SERVICE}"))
        assert_equal "Thermostat S\u00e9jour", found.name
        assert_equal ["AA:BB", "BR01"], [found.id, found.model]
    end

    def test_garbled_bytes_in_a_name_are_replaced
        found = decode(answer(instance: "Bad \xFF.#{SERVICE}".b))
        assert_equal "Bad \uFFFD", found.name
    end

    def test_the_query_leaves_on_the_interface_given
        address = ipv4_address or skip "no IPv4 interface"
        socket  = Discovery.new(address).send(:listener)
        assert_equal address, multicast_interface(socket)
    ensure
        socket&.close
    end

    private

    def ipv4_address
        Socket.ip_address_list.find { it.ipv4? && !it.ipv4_loopback? }
              &.ip_address
    end

    def multicast_interface(socket)
        data = socket.getsockopt(:IPPROTO_IP, :IP_MULTICAST_IF).data
        IPAddr.new_ntoh(data[0, 4]).to_s
    end

    # The service found in packet, as browse would report it.
    def decode(packet)
        discovery = Discovery.new("0.0.0.0")
        discovery.send(:record, packet)
        discovery.send(:services).first
    end

    def answer(srv: true, instance: INSTANCE)
        message = Resolv::DNS::Message.new(0)
        message.qr = 1
        message.add_answer(SERVICE, 120, IN::PTR.new(dns_name(instance)))
        records(srv, dns_name(instance)).each do |name, data|
            message.add_answer(name, 120, data)
        end
        message.encode
    end

    def records(srv, instance)
        list = [[instance, flush(IN::TXT).new("id=AA:BB", "md=BR01", "sf=1")],
                ["bridge.local", flush(IN::A).new("192.0.2.7")]]
        return list unless srv
        target = dns_name("bridge.local")
        list << [instance, flush(IN::SRV).new(0, 0, 51_826, target)]
    end

    # Resolv encodes labels as bytes: a UTF-8 one must come as such.
    def dns_name(text) = Resolv::DNS::Name.create(text.b)

    # The record type with mDNS's cache-flush bit set on its class.
    def flush(type)
        Class.new(type).tap { it.const_set(:ClassValue, 0x8001) }
    end
end

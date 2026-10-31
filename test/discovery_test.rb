# frozen_string_literal: true

require "test_helper"

# Discovery's decoding of an mDNS answer, without a network: the
# records an accessory sends, with the cache-flush bit mDNS sets on
# their class.
class DiscoveryTest < Minitest::Test
    Discovery = HomeKit::Controller::Discovery
    IN        = Resolv::DNS::Resource::IN
    INSTANCE  = "Bridge 1._hap._tcp.local"

    def test_a_cache_flush_answer_gives_the_service
        found = decode(answer)
        assert_equal ["Bridge 1", "192.0.2.7", 51_826, "AA:BB", "BR01", 1],
                     found.to_h.values
        refute_predicate found, :paired?
    end

    def test_an_answer_without_its_srv_gives_nothing
        assert_nil decode(answer(srv: false))
    end

    private

    def decode(packet)
        discovery = Discovery.new("0.0.0.0")
        discovery.send(:record, packet)
        discovery.send(:service, INSTANCE)
    end

    def answer(srv: true)
        message = Resolv::DNS::Message.new(0)
        message.qr = 1
        message.add_answer(Discovery::SERVICE, 120, IN::PTR.new(dns_name(INSTANCE)))
        records(srv).each { |name, data| message.add_answer(name, 120, data) }
        message.encode
    end

    def records(srv)
        list = [[INSTANCE, flush(IN::TXT).new("id=AA:BB", "md=BR01", "sf=1")],
                ["bridge.local", flush(IN::A).new("192.0.2.7")]]
        return list unless srv
        target = dns_name("bridge.local")
        list << [INSTANCE, flush(IN::SRV).new(0, 0, 51_826, target)]
    end

    def dns_name(text) = Resolv::DNS::Name.create(text)

    # The record type with mDNS's cache-flush bit set on its class.
    def flush(type)
        Class.new(type).tap { it.const_set(:ClassValue, 0x8001) }
    end
end

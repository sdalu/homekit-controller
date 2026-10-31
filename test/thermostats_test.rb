# frozen_string_literal: true

require "test_helper"

# Thermostats on a fake session: reading, finding, setting.
class ThermostatsTest < Minitest::Test
    # Shaped like GET /accessories from a thermostat bridge: information
    # service, then a thermostat, types in long and short form.
    ACCESSORY = {
        "aid" => 2,
        "services" => [
            { "type" => "0000003E-0000-1000-8000-0026BB765291", "iid" => 1,
              "characteristics" => [
                  { "type" => "23", "iid" => 2, "value" => "Living room" }
              ] },
            { "type" => "4A", "iid" => 8,
              "characteristics" => [
                  { "type" => "11", "iid" => 9, "value" => 19.4 },
                  { "type" => "35", "iid" => 10, "value" => 20.0,
                    "minValue" => 5, "maxValue" => 25 },
                  { "type" => "10", "iid" => 11, "value" => 48.6 },
                  { "type" => "0000000F-0000-1000-8000-0026BB765291",
                    "iid" => 12, "value" => 1 },
                  { "type" => "33", "iid" => 13, "value" => 3,
                    "valid-values" => [0, 1, 3] }
              ] }
        ]
    }.freeze

    FakeClient = Struct.new(:writes) do
        def accessories = [{ "aid" => 1, "services" => [] }, ACCESSORY]
        def write(values) = writes << values
    end

    def setup
        @client = FakeClient.new([])
        @thermostats = HomeKit::Controller::Thermostats.new(@client)
    end

    def test_reads_device_state
        device = @thermostats.find("living room")
        assert_equal ["Living room", 19.4, 20.0, 48.6, :auto],
                     [device.name, device.current_temperature,
                      device.target_temperature, device.humidity, device.mode]
        assert_predicate device, :heating?
    end

    def test_sets_temperature_within_range
        @thermostats.set_temperature("Living room", "21.5")
        assert_equal [{ [2, 10] => 21.5 }], @client.writes
        assert_raises(ArgumentError) do
            @thermostats.set_temperature("Living room", 30)
        end
    end

    def test_sets_only_modes_the_bridge_offers
        @thermostats.set_mode("Living room", "off")
        assert_equal [{ [2, 13] => 0 }], @client.writes
        assert_raises(ArgumentError) do
            @thermostats.set_mode("Living room", "cool")
        end
    end

    def test_finds_by_unique_part_of_its_name
        assert_equal 2, @thermostats.find("LIVING").aid
    end

    def test_unknown_thermostat
        assert_raises(ArgumentError) { @thermostats.find("Attic") }
    end
end

# frozen_string_literal: true

module HomeKit
    module Controller
        # One thermostat: an accessory of GET /accessories with a
        # Thermostat service. characteristics maps a name from
        # CHARACTERISTICS to the characteristic's JSON (iid, value,
        # minValue, valid-values...). Subclass it to add what a maker's
        # devices carry beyond HomeKit; from_accessory builds the
        # subclass.
        Thermostat = Data.define(:aid, :name, :serial, :model,
                                 :characteristics)

        class Thermostat
            SERVICE     = "4A"
            INFORMATION = "3E"

            # The characteristic types read, by the name they go by.
            CHARACTERISTICS = {
                "23" => :name,
                "30" => :serial,
                "21" => :model,
                "11" => :current_temperature,
                "35" => :target_temperature,
                "10" => :humidity,
                "F" => :heating_state,
                "33" => :mode
            }.freeze

            # Target heating/cooling state values.
            MODES = { off: 0, heat: 1, cool: 2, auto: 3 }.freeze

            # nil when the accessory has no Thermostat service.
            def self.from_accessory(accessory)
                services   = accessory.fetch("services")
                thermostat = find(services, SERVICE) or return
                found      = characteristics(thermostat)
                info       = characteristics(find(services, INFORMATION))
                name = (found[:name] || info[:name])&.fetch("value")
                new(aid: accessory.fetch("aid"), name: name.to_s,
                    serial: info[:serial]&.fetch("value"),
                    model: info[:model]&.fetch("value"),
                    characteristics: found)
            end

            def self.find(services, type)
                services.find { type_of(it) == type }
            end

            def self.characteristics(service)
                service.to_h.fetch("characteristics", []).filter_map do |spec|
                    key = CHARACTERISTICS[type_of(spec)]
                    [key, spec] if key
                end.to_h
            end

            def self.type_of(spec) = Controller.short_type(spec.fetch("type"))

            def current_temperature = value(:current_temperature)
            def target_temperature  = value(:target_temperature)
            def humidity            = value(:humidity)
            def heating?            = value(:heating_state) == 1
            def mode                = MODES.key(value(:mode))

            def iid(key) = characteristic(key).fetch("iid")

            # [min, max, step] the target temperature takes; the step is
            # 0.1 when the accessory gives none, min and max nil.
            def target_range
                spec = characteristic(:target_temperature)
                [spec["minValue"]&.to_f, spec["maxValue"]&.to_f,
                 spec.fetch("minStep", 0.1).to_f]
            end

            # Whether the accessory accepts value for a characteristic.
            def accepts?(key, value)
                spec  = characteristic(key)
                valid = spec["valid-values"]
                return valid.include?(value) if valid
                (spec.fetch("minValue", value)..spec.fetch("maxValue", value))
                    .cover?(value)
            end

            def characteristic(key)
                characteristics.fetch(key) do
                    raise ProtocolError, "#{name}: no #{key} exposed"
                end
            end

            # A characteristic's value, nil when not exposed.
            def value(key) = characteristics[key]&.fetch("value", nil)
        end
    end
end

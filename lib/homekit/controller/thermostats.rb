# frozen_string_literal: true

module HomeKit
    module Controller
        # The thermostats behind one open session (Client): found by name,
        # set by target temperature and mode. kind: the Thermostat class
        # to build, a subclass to carry a maker's extras.
        class Thermostats
            def initialize(client, kind: Thermostat)
                @client = client
                @kind   = kind
            end

            def all
                @client.accessories.filter_map { @kind.from_accessory(it) }
            end

            # The one whose name is name (any case), else the one whose
            # name contains it (a bridge names its devices after model and
            # serial, so the serial alone will do).
            def find(name)
                all   = self.all
                exact = all.find { it.name.casecmp?(name) }
                return exact if exact
                found = all.select { it.name.downcase.include?(name.downcase) }
                return found.first if found.one?
                raise ArgumentError, "#{found.empty? ? "no" : "several"} " \
                                     "thermostats match #{name.inspect}"
            end

            def set_temperature(name, celsius)
                update(find(name), :target_temperature, Float(celsius))
            end

            # mode: a key of Thermostat::MODES.
            def set_mode(name, mode)
                value = Thermostat::MODES.fetch(mode.to_sym) do
                    raise ArgumentError, "unknown mode #{mode}"
                end
                update(find(name), :mode, value)
            end

            private

            def update(thermostat, key, value)
                unless thermostat.accepts?(key, value)
                    raise ArgumentError,
                          "#{thermostat.name}: #{key} cannot be #{value}"
                end
                @client.write([thermostat.aid, thermostat.iid(key)] => value)
            end
        end
    end
end

# homekit-controller

The controller side of HomeKit, over IP: what an iPhone does when it
talks to an accessory on the local network. It pairs with an accessory
by its setup code, opens an encrypted session, reads and writes
characteristics, finds accessories by mDNS, and drives thermostats.

It needs only Ruby's standard library: Ruby 3.4 with OpenSSL 3 (SRP's
SHA-512, Ed25519, X25519, ChaCha20-Poly1305).

## Use

```ruby
require "homekit/controller"

hap = HomeKit::Controller

hap::Discovery.browse.each { puts "#{it.name} #{it.host}:#{it.port}" }

# Once: pair with the code on the accessory, and keep the pairing.
pairing = hap::Client.pair("192.168.1.20", 80, "123-45-678")
pairing.save("pairing.json")

# Then for each session:
hap::Client.open(hap::Pairing.load("pairing.json")) do |client|
    thermostats = hap::Thermostats.new(client)
    thermostats.all.each do |t|
        puts "#{t.name}: #{t.current_temperature} °C -> #{t.target_temperature}"
    end
    thermostats.set_temperature("living", 20.5)
    thermostats.set_mode("living", :heat)
end
```

- `Client#accessories` is GET /accessories; `Client#read(*ids)` reads
  characteristics by `[aid, iid]`, and `Client#write` takes
  `{ [aid, iid] => value }`.
- `Client#subscribe(*ids)` has the accessory send changes to those
  characteristics (those with `"ev"` in their `perms`) for as long as
  the session lasts, and `Client#next_event(timeout:)` takes the next,
  as `{ [aid, iid] => value }`, or nil once the timeout passes. When
  the accessory closes the session, `next_event` raises `EOFError`: open
  a new one and subscribe again.
- `Thermostats#find(name)` takes the full name, any case, or any part of
  it that picks out one thermostat.
- `Thermostat` reads the HomeKit Thermostat service: current and target
  temperature, humidity, heating state, mode, the target's range, and
  whether a value is accepted. Subclass it for what a maker's devices
  carry beyond HomeKit, and pass the subclass as
  `Thermostats.new(client, kind: MyThermostat)`.

An accessory holds a single controller pairing and commits to it during
pair-setup, so keep the pairing file safe: losing its key leaves the
accessory paired to nobody reachable, which only a factory reset
undoes. `Pairing.reserve(path)` creates the file before pairing, so an
unwritable path fails while nothing is lost yet.

Errors are `HomeKit::Controller::Error` and its subclasses
`ProtocolError`, `AuthenticationError` and `PairingError`; the network's
own (`SystemCallError`, `IOError`, `Timeout::Error`) pass through.

## Known shortfalls

- IP accessories only: no Bluetooth LE, no Thread.
- Events are taken one session at a time, by the caller: no thread
  reads them, and nothing reconnects or resubscribes on its own.
- Adding another controller's pairing is not built; removing one is
  (`Client#remove_pairing`), which is how `unpair` frees an accessory.

## Development

```sh
bundle install
bundle exec rake    # tests, then RuboCop
```

Licence: MIT (LICENSE.txt).

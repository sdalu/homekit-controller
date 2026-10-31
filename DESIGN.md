# Design

## HAP from the standard library

The controller is written against Ruby's OpenSSL bindings, with no HAP
gem or native code: SRP-6a pair-setup with the accessory's setup code,
then for each session an X25519 pair-verify signed by both sides'
Ed25519 keys, and ChaCha20-Poly1305 frames carrying HTTP and JSON. The
protocol is small, and every step is checked by a test: SRP against
Apple's published vectors, the handshakes against a fake accessory
written from the specification, and each refusal by feeding it a
forgery.

Pair-setup has the accessory run 3072-bit SRP arithmetic, which a
bridge's small CPU can take tens of seconds over, so pairing waits
longer (90 s) than a session's requests (10 s).

## Pairing kept safe before it exists

An accessory holds a single controller pairing, and commits to it
before the controller has saved its key. `Pairing.reserve` therefore
creates the pairing file before the accessory is contacted, so an
unwritable path fails while nothing is lost; a caller whose save still
fails should print the pairing rather than drop it.

## Discovery on the multicast group

Discovery listens on the mDNS multicast group rather than asking for
unicast replies (RFC 6762 §6.7): a stateful firewall drops unicast
replies, since they come from the accessory and not from the address
queried. Resolv is taught mDNS's cache-flush class bit, which it would
otherwise decode as an unknown record type.

## Thermostats generic, makers by subclass

`Thermostat` reads only what HomeKit defines for the Thermostat service,
so it works with any maker's thermostat. What a maker adds (its model
codes, how its bridge names devices, what its overlays do) belongs to
the application, by subclassing `Thermostat`; `Thermostats` builds
whichever class it is given. The protocol layer knows nothing of
thermostats.

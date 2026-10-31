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

## Events on the caller's thread

An accessory sends a subscribed characteristic's changes on the session
it was subscribed on, as `EVENT/1.0` messages between the replies. The
session reads them only when asked (`Client#next_event`, which also
hands over those met while waiting for a reply), rather than from a
thread of its own: the encrypted frames are numbered, so one reader
must own the socket. Only the start of a message is waited for, with
the caller's timeout; once one begins it is read whole, so a timeout
never leaves the stream cut in two.

## A session cut short is closed

A reply that times out may still arrive, and would then be read as the
reply to the next request. So whatever cuts an exchange short closes
the session; the caller opens another. For the same reason the event
wait only times out between messages, and what the other end sends is
bounded and checked before it is trusted: lengths as HTTP writes them,
a line and a body of limited size, keys of the right length, JSON of
the right shape, each failure a ProtocolError or AuthenticationError
rather than whatever the parser raised. Pair-verify reads its first
reply before anything is authenticated, from whatever answers at the
accessory's address.

## Watching across sessions

`Client.watch` retries what the network does (refused or lost
connections, timeouts) and nothing else: a refused subscription and a
pairing the accessory no longer accepts would fail the same way every
time, and what the caller's block raises is the caller's. It reads every
value on each connection, as changes made while away send no event,
and probes a quiet session, as an accessory that loses power sends no
word. The wait between attempts doubles, and returns to its shortest
only once a session has brought a change, so that an accessory which
accepts and then drops connections is not hammered.

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

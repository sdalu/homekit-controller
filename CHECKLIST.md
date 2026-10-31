# Closing a round on homekit-controller

## Gates

- [ ] `bundle exec rake` passes: tests, then RuboCop.
- [ ] A real accessory still reads, if the protocol layer changed: open
  a session with an existing pairing and list its accessories. Never
  pair or unpair as a check: an accessory takes one pairing, and a lost
  one needs a factory reset.

## Documents

- [ ] `README.md`: do the examples still run, and are the known
  shortfalls still the true ones?
- [ ] `DESIGN.md`: did this round change a reason it gives, or make a
  choice it should record?

## Release

- [ ] Does `HomeKit::Controller::VERSION` in
  `lib/homekit/controller/version.rb` move with this round? It is the
  one place the release number is written.

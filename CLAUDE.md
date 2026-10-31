# homekit-controller

How it works: README.md. Why it is shaped so: DESIGN.md. What closes a
round: CHECKLIST.md.

Gate: `bundle exec rake`

Ruby style: the `ruby` skill (4-space indentation, double quotes,
`.rubocop.yml` is its rule set).

## Traps

- Pairing with a real accessory, or unpairing it, is irreversible from
  here: it takes one controller, and a lost pairing key needs a factory
  reset. Tests use test/support/fake_accessory.rb; never pair as a
  check.
- ClimatControl (~/Repos/ClimatControl) uses this gem through a path in
  its Gemfile: a change here is live there at once, so run its gate too.

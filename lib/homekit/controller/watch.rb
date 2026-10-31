# frozen_string_literal: true

module HomeKit
    module Controller
        # Follows characteristics ([aid, iid] pairs, "ev" among their
        # perms) across sessions, for as long as the caller wants: #each
        # yields { [aid, iid] => value } for all of them on each
        # connection, so that nothing changed while away goes unseen, then
        # each change as it comes.
        #
        # A session quiet for idle seconds is probed with a read, so that
        # an accessory gone without a word (power cut, Wi-Fi lost) is
        # noticed within idle + timeout seconds. After a network failure
        # it connects again, waiting backoff.begin seconds, doubled each
        # time up to backoff.end, and back to backoff.begin once a session
        # has brought a change; lost, when given, is called with each
        # network error. Other errors end the watch: a refused
        # subscription, and AuthenticationError or PairingError, which say
        # the pairing is no longer good, are not for retrying.
        class Watch
            NETWORK  = [SystemCallError, IOError, SocketError].freeze
            DEFAULTS = { idle: 60, backoff: 1..60, timeout: Client::TIMEOUT,
                         lost: nil }.freeze

            # options: idle, backoff, timeout and lost, as above.
            def initialize(pairing, ids, **options)
                unknown = options.keys - DEFAULTS.keys
                raise ArgumentError, "unknown options #{unknown}" if
                    unknown.any?
                raise ArgumentError, "nothing to watch" if ids.empty?
                @pairing = pairing
                @ids     = ids
                DEFAULTS.merge(options).each do |name, value|
                    instance_variable_set(:"@#{name}", value)
                end
            end

            # Returns only when the block breaks out of it, or raises.
            def each(&)
                delay = @backoff.begin
                loop do
                    session = guard { connect }
                    delay = @backoff.begin if session && follow(*session, &)
                    sleep(delay)
                    delay = [delay * 2, @backoff.end].min
                end
            end

            private

            # [client, values]: a session subscribed, and the values as
            # they stand once it is.
            def connect
                client = Client.connect(@pairing, timeout: @timeout)
                client.subscribe(*@ids)
                [client, client.values(*@ids)]
            rescue StandardError
                client&.close
                raise
            end

            # Yields values, then each change, until the session fails;
            # whether a change came. Only the session's own calls are
            # guarded: what the caller's block raises is the caller's, and
            # goes through.
            def follow(client, values)
                changed = false
                while values
                    yield values
                    values  = guard { change(client) }
                    changed = true if values
                end
                changed
            ensure
                client.close
            end

            def change(client)
                loop do
                    values = client.next_event(timeout: @idle)
                    return values if values
                    client.read(@ids.first)
                end
            end

            # The block's value; nil when the network failed it.
            def guard
                yield
            rescue *NETWORK => e
                @lost&.call(e)
                nil
            end
        end
    end
end

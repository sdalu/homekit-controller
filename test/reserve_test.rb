# frozen_string_literal: true

require "tmpdir"

require "test_helper"

# Pairing.reserve: the file a pairing will go to, created before the
# accessory commits to a pairing, so that a path that cannot hold the
# key fails while nothing is lost.
class ReserveTest < Minitest::Test
    Pairing = HomeKit::Controller::Pairing

    def test_creates_an_empty_private_file
        Dir.mktmpdir do |dir|
            path = File.join(dir, "homekit", "pairing.json")
            Pairing.reserve(path)
            assert_equal [0, 0o600], [File.size(path),
                                      File.stat(path).mode & 0o777]
        end
    end

    # An existing pairing is never overwritten by a new pair-setup.
    def test_refuses_a_path_that_exists
        Dir.mktmpdir do |dir|
            path = File.join(dir, "pairing.json")
            File.write(path, "{}")
            assert_raises(Errno::EEXIST) { Pairing.reserve(path) }
            assert_equal "{}", File.read(path)
        end
    end

    def test_refuses_a_directory_it_cannot_write
        Dir.mktmpdir do |dir|
            File.chmod(0o500, dir)
            skip "running as root: permissions do not refuse" if
                Process.uid.zero?
            assert_raises(Errno::EACCES) do
                Pairing.reserve(File.join(dir, "pairing.json"))
            end
        ensure
            File.chmod(0o700, dir)
        end
    end
end

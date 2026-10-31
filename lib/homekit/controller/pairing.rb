# frozen_string_literal: true

require "fileutils"
require "json"
require "openssl"

module HomeKit
    module Controller
        # What pair-setup leaves behind: our identity (an id and an Ed25519
        # key) and the accessory's, plus where to reach it. The file holds
        # a private key, so it is written readable by its owner only.
        Pairing = Data.define(:controller_id, :controller_key,
                              :accessory_id, :accessory_key,
                              :host, :port) do
            # A damaged file is reported without quoting it: the parser's
            # messages would echo its content, private key included.
            def self.load(path)
                data = JSON.parse(File.read(path), symbolize_names: true)
                new(**data,
                    controller_key: [data.fetch(:controller_key)].pack("H*"),
                    accessory_key: [data.fetch(:accessory_key)].pack("H*"))
            rescue JSON::ParserError, KeyError, TypeError, NoMethodError,
                   ArgumentError
                raise Error, "#{path}: not a valid pairing file"
            end

            # Creates an empty, owner-only file at path before pairing, so
            # that a path where the key could not be saved fails before the
            # accessory commits to it. Raises Errno::EEXIST if one exists.
            def self.reserve(path)
                FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
                File.open(path, File::WRONLY | File::CREAT | File::EXCL,
                          0o600, &:close)
            end

            def save(path)
                FileUtils.mkdir_p(File.dirname(path), mode: 0o700)
                File.write(path, JSON.pretty_generate(to_json_hash),
                           perm: 0o600)
                File.chmod(0o600, path)
            end

            def signing_key
                OpenSSL::PKey.new_raw_private_key("ED25519", controller_key)
            end

            def to_json_hash
                to_h.merge(controller_key: controller_key.unpack1("H*"),
                           accessory_key: accessory_key.unpack1("H*"))
            end
        end
    end
end

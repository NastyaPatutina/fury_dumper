# frozen_string_literal: true

module FuryDumper
  class Encrypter
    KEY = "\xBE\nXx\xE2\xDB\x85\xBD\xE1j}qz?}\xB0j6\xA95\xBAy80\x95\xE6\xC1\x9D\x9F\x89\xA2t"

    def self.encrypt(msg)
      crypt = ActiveSupport::MessageEncryptor.new(KEY)
      crypt.encrypt_and_sign(msg)
    end

    def self.decrypt(encrypted_data)
      crypt = ActiveSupport::MessageEncryptor.new(KEY)
      crypt.decrypt_and_verify(encrypted_data)
    end
  end
end

require 'fileutils'
require 'securerandom'

# Only generated names in a private, owner-specific directory may be read/deleted.
class EqualizedAudio
  class ProcessingError < StandardError; end

  FILTERS = {
    highpass: 'c0 f=0 w=3000 g=-96 t=2|c1 f=0 w=3000 g=-96 t=2',
    radio: 'c0 f=0 w=2500 g=-96 t=2|c1 f=0 w=2500 g=-96 t=2|' \
           'c0 f=15000 w=16000 g=-96 t=2|c1 f=15000 w=16000 g=-96 t=2',
    lowpass: 'c0 f=15000 w=16000 g=-96 t=2|c1 f=15000 w=16000 g=-96 t=2',
    vocal: 'c0 f=3000 w=2000 g=10 t=2|c1 f=3000 w=2000 g=10 t=2'
  }.freeze
  NAME = /\A[0-9a-f]{32}\.(?:wav|aac|mp3|m4a)\z/

  def self.root
    Rails.root.join('tmp', 'equalized_audio')
  end

  def self.directory(user_id, create: false)
    return unless /\A[1-9][0-9]*\z/.match?(user_id.to_s)
    return if File.symlink?(root)

    directory = root.join(user_id.to_s)
    return if File.symlink?(directory)

    FileUtils.mkdir_p(directory, mode: 0o700) if create
    return unless File.directory?(directory)
    return unless directory.realpath.dirname == root.realpath

    directory
  end

  def self.path_for(user_id, name)
    return unless name.is_a?(String) && NAME.match?(name)

    directory = directory(user_id)
    return unless directory

    path = directory.join(name)
    return if File.symlink?(path) || !File.file?(path)
    return unless path.realpath.dirname == directory.realpath

    path.to_s
  end

  def self.remove(user_id, name)
    path = path_for(user_id, name)
    File.delete(path) if path
  end

  def self.create(input, direction, user_id:)
    filter = FILTERS.fetch(direction)
    directory = directory(user_id, create: true)
    raise ProcessingError, 'Invalid output directory' unless directory

    name = "#{SecureRandom.hex(16)}#{File.extname(input.original_filename).downcase}"
    path = directory.join(name).to_s
    unless convert(input.path, path, filter) && path_for(user_id, name)
      remove(user_id, name)
      raise ProcessingError, 'FFmpeg failed'
    end
    name
  end

  def self.convert(input_path, output_path, filter)
    # No shell, and no client-controlled filename in the output path. FFmpeg may
    # only read local files (not network resources referenced by uploaded media).
    system('ffmpeg', '-nostdin', '-n', '-loglevel', 'error',
           '-protocol_whitelist', 'file', '-format_whitelist', 'wav,aac,mp3,mov', '-i', input_path,
           '-af', "anequalizer=#{filter}", output_path)
  end
end

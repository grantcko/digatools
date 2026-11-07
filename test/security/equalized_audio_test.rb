# Standalone regressions: ruby test/security/equalized_audio_test.rb
# No application database or live service is used.
ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest', '~> 5.0'
require 'minitest/autorun'
require 'minitest/mock'
require 'tmpdir'
require 'pathname'
require 'ostruct'
require_relative '../../app/services/equalized_audio'

module Rails
  def self.root
    Pathname.new(Dir.pwd)
  end
end unless defined?(Rails)

class EqualizedAudioTest < Minitest::Test
  def setup
    @scratch = Dir.mktmpdir('digatools-security-')
    @root = Pathname.new(@scratch).join('private')
    @name = "#{'a' * 32}.wav"
  end

  def teardown
    FileUtils.remove_entry(@scratch)
  end

  def in_store(&block)
    EqualizedAudio.stub(:root, @root, &block)
  end

  def write_output(owner = 1)
    directory = EqualizedAudio.directory(owner, create: true)
    directory.join(@name).write('synthetic')
    directory.join(@name)
  end

  def test_owner_isolation_and_safe_deletion
    in_store do
      path = write_output
      assert_equal path.to_s, EqualizedAudio.path_for(1, @name)
      assert_nil EqualizedAudio.path_for(2, @name)
      EqualizedAudio.remove(2, @name)
      assert path.exist?
      EqualizedAudio.remove(1, @name)
      refute path.exist?
      EqualizedAudio.remove(1, @name) # expired jobs are idempotent
    end
  end

  def test_traversal_and_shell_strings_are_never_resolved_or_deleted
    in_store do
      path = write_output
      [nil, [], {}, '../outside.wav', "/tmp/#{@name}", "../1/#{@name}",
       "..\\1\\#{@name}", '%2e%2e%2foutside.wav', "#{@name};echo harmless",
       "#{@name}\0", "\n#{@name}"].each do |name|
        assert_nil EqualizedAudio.path_for(1, name)
        EqualizedAudio.remove(1, name)
      end
      [nil, '../1', '/tmp', '01', '1/..', 0, -1].each do |owner|
        assert_nil EqualizedAudio.path_for(owner, @name)
      end
      assert path.exist?
    end
  end

  def test_symlink_file_and_directory_cannot_escape
    in_store do
      directory = EqualizedAudio.directory(1, create: true)
      outside = Pathname.new(@scratch).join('outside.wav')
      outside.write('preserve')
      File.symlink(outside, directory.join(@name))
      assert_nil EqualizedAudio.path_for(1, @name)
      EqualizedAudio.remove(1, @name)
      assert_equal 'preserve', outside.read
      File.symlink(directory, @root.join('2'))
      assert_nil EqualizedAudio.directory(2, create: true)
    end
  end

  def test_symlink_store_is_rejected
    real = Pathname.new(@scratch).join('real')
    real.mkdir
    File.symlink(real, @root)
    in_store { assert_nil EqualizedAudio.directory(1, create: true) }
  end

  def test_shell_metacharacters_are_not_used_in_output_and_input_is_a_single_argument
    in_store do
      input = OpenStruct.new(original_filename: '../test;echo harmless$(echo harmless).wav',
                             path: '/tmp/audio with spaces;echo harmless.wav')
      runner = lambda do |*args|
        assert_equal 'ffmpeg', args.first
        assert_equal input.path, args[args.index('-i') + 1]
        assert_equal 'file', args[args.index('-protocol_whitelist') + 1]
        assert_equal @root.join('1').to_s, File.dirname(args.last)
        assert_match EqualizedAudio::NAME, File.basename(args.last)
        refute_includes args.last, 'harmless'
        File.write(args.last, 'synthetic')
        true
      end
      EqualizedAudio.stub(:system, runner) do
        name = EqualizedAudio.create(input, :radio, user_id: 1)
        assert EqualizedAudio.path_for(1, name)
      end
    end
  end

  def test_failed_conversion_removes_partial_output
    in_store do
      input = OpenStruct.new(original_filename: 'input.wav', path: '/tmp/input.wav')
      runner = ->(*args) { File.write(args.last, 'partial'); false }
      EqualizedAudio.stub(:system, runner) do
        assert_raises(EqualizedAudio::ProcessingError) { EqualizedAudio.create(input, :radio, user_id: 1) }
      end
      assert_empty @root.join('1').children
    end
  end

  def test_real_ffmpeg_converts_synthetic_stereo_wave_for_every_preset
    in_store do
      # PCM silence, generated in memory; no user recordings are read.
      input_path = Pathname.new(@scratch).join('input with spaces;harmless.wav')
      samples = "\0".b * 17_640
      wave = 'RIFF' + [36 + samples.bytesize].pack('V') + 'WAVEfmt ' +
             [16, 1, 2, 44_100, 176_400, 4, 16].pack('VvvVVvv') +
             'data' + [samples.bytesize].pack('V') + samples
      input_path.binwrite(wave)
      input = OpenStruct.new(path: input_path.to_s, original_filename: 'a;harmless.wav')
      EqualizedAudio::FILTERS.each_key do |direction|
        name = EqualizedAudio.create(input, direction, user_id: 1)
        path = EqualizedAudio.path_for(1, name)
        assert File.size(path) > 44
        assert_nil EqualizedAudio.path_for(2, name)
        EqualizedAudio.remove(1, name)
      end
    end
  end
end

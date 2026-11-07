# Synthetic PCM silence; no personal media is needed by the test suite.
def build_test_audio(filename, content_type)
  samples = "\0".b * 17_640
  wave = ['RIFF', [36 + samples.bytesize].pack('V'), 'WAVEfmt ',
          [16, 1, 2, 44_100, 176_400, 4, 16].pack('VvvVVvv'),
          'data', [samples.bytesize].pack('V'), samples].join
  tempfile = Tempfile.new('synthetic_audio')
  tempfile.binmode
  tempfile.write(wave)
  tempfile.rewind
  ActionDispatch::Http::UploadedFile.new(tempfile: tempfile, type: content_type, filename: filename)
end

def build_test_mpeg
  build_test_audio('synthetic.mp3', 'audio/mpeg')
end

def build_test_mov
  build_test_audio('synthetic.mov', 'video/quicktime')
end

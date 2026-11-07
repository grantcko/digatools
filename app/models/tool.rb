class Tool < ApplicationRecord
  EQ_DIRECTIONS = %i[highpass radio lowpass vocal]
  INTERNALS = ['custom', 'color_picker', 'auto_equalizer', 'prompt_generator', 'photo_ideator']

  belongs_to :user

  validates :name, presence: true
  validates :internals, presence: true
  validates :internals, inclusion: { in: INTERNALS, message: "is not a valid item" }, allow_nil: true
  validate :internal_array?

  def internal_array?
    unless internals.is_a?(Array)
      errors.add(:my_column, "must be an array")
      return false
    end
    true
  end

  def self.valid_direction?(direction)
    # raise
    return false if EQ_DIRECTIONS.exclude?(direction)

    return true
  end

  def self.valid_audio_input?(file)
    file.is_a?(ActionDispatch::Http::UploadedFile) &&
      %w[.wav .aac .mp3 .m4a].include?(File.extname(file.original_filename.to_s).downcase)
  end

  def self.equalize(audio_input, direction, user_id:)
    raise ArgumentError, "Invalid audio_input" unless valid_audio_input?(audio_input)
    raise ArgumentError, "Invalid direction" unless valid_direction?(direction)

    EqualizedAudio.create(audio_input, direction, user_id: user_id)
  end
end

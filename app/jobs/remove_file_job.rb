class RemoveFileJob < ApplicationJob
  def perform(user_id, output_name)
    EqualizedAudio.remove(user_id, output_name)
  end
end

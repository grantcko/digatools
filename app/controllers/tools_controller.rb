require 'faker'

class ToolsController < ApplicationController
  DEMO_PARTIALS = {
    'color_picker' => 'color_picker',
    'prompt_generator' => 'prompt_generator',
    'photo_ideator' => 'photo_ideator'
  }.freeze

  before_action :authenticate_user!
  skip_before_action :authenticate_user!, only: [:demo_show, :demo_index]
  before_action :set_owned_tool, only: %i[show update destroy equalize_audio]

  def download
    path = EqualizedAudio.path_for(current_user.id, params[:file])
    return head :not_found unless path

    send_file path, disposition: "attachment"
  end

  def equalize_audio
    direction = params[:direction].to_s.to_sym
    input = params[:file]
    unless Tool.valid_direction?(direction) && Tool.valid_audio_input?(input)
      return render json: { error: "Invalid audio or direction" }, status: :unprocessable_entity
    end

    output = Tool.equalize(input, direction, user_id: current_user.id)
    RemoveFileJob.set(wait: 5.minutes).perform_later(current_user.id, output)
    render json: { output: output }
  rescue EqualizedAudio::ProcessingError
    render json: { error: "Audio processing failed" }, status: :unprocessable_entity
  end

  def index
    @tools = current_user.tools
    @column_one = @tools.where(column: 1)
    @column_two = @tools.where(column: 2)
    @column_three = @tools.where(column: 3)
  end

  def demo_index
    tools = []
    Tool::INTERNALS.each do |internal|
      tools << internal
    end
    tools.delete('auto_equalizer')
    tools.delete('custom')
    @tools = tools
  end

  def show
    @eq_directions = Tool::EQ_DIRECTIONS
    @photo_idea = random_photo_idea
  end

  def demo_show
    @tool = DEMO_PARTIALS[params[:internal]]
    return head :not_found unless @tool

    @eq_directions = Tool::EQ_DIRECTIONS
    @photo_idea = random_photo_idea
  end

  def new
    @tool = Tool.new
    @column = params[:col]
    @all_internals = Tool::INTERNALS
  end

  def create
    @tool = Tool.new(tool_params)
    @tool.user = current_user
    @tool.column = tool_params[:column]
    @tool.internals << tool_params[:internals]
    @tool.links << tool_params[:links]

    authorize @tool
    if @tool.save
      redirect_to @tool
    else
      redirect_to new_tool_path, status: :unprocessable_entity
    end
  end

  def update
    # update and instance of a tool
    if @tool.update(tool_params)
      redirect_to @tool
    else
      render json: { error: @tool.errors.full_messages }, status: :unprocessable_entity
    end
  end

  def destroy
    @tool.destroy
  end

  private

  def set_owned_tool
    id = action_name == "equalize_audio" ? params[:tool_id] : params[:id]
    @tool = current_user.tools.find(id)
    authorize @tool, action_name == "equalize_audio" ? :update? : "#{action_name}?"
  end

  # returns a hash with the photo idea information
  def random_photo_idea
    noun = Faker::Appliance.equipment
    ideas = YAML.load_file(Rails.root.join('config', 'photo_ideas.yml'))
    random_idea = ideas['ideas'].sample
    idea_items = random_idea['items'].map { |item| item % { noun: } }
    idea_sentence = random_idea['idea'] % { noun: }
    return { idea_sentence:, idea_items: }
  end

  def tool_params
    params.require(:tool).permit(:name, :note, :internals, :links, :column)
  end
end

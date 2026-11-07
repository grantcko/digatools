require 'rails_helper'
require 'tmpdir'

RSpec.describe 'Tool security', type: :request do # rubocop:disable Metrics/BlockLength
  include Devise::Test::IntegrationHelpers

  let!(:owner) { User.create!(email: 'owner@example.invalid', password: 'test-password-123') }
  let!(:other) { User.create!(email: 'other@example.invalid', password: 'test-password-123') }
  let!(:tool) { Tool.create!(user: owner, name: 'Synthetic tool', internals: ['auto_equalizer']) }

  before do
    @scratch = Dir.mktmpdir('digatools-requests-')
    allow(EqualizedAudio).to receive(:root).and_return(Pathname.new(@scratch).join('outputs'))
  end

  after do
    FileUtils.remove_entry(@scratch) if @scratch
  end

  it 'denies non-owners in the policy as well as the controller scope' do
    %i[show? update? destroy? create?].each do |query|
      expect(ToolPolicy.new(owner, tool).public_send(query)).to be(true)
      expect(ToolPolicy.new(other, tool).public_send(query)).to be(false)
      expect(ToolPolicy.new(nil, tool).public_send(query)).to be(false)
    end
    expect(ToolPolicy::Scope.new(other, Tool).resolve).not_to include(tool)
  end

  it 'runs cleanup without a shell and cannot remove another owner output' do
    name = "#{'a' * 32}.wav"
    path = EqualizedAudio.directory(owner.id, create: true).join(name)
    path.write('synthetic output')
    RemoveFileJob.perform_now(other.id, name)
    RemoveFileJob.perform_now(owner.id, "../#{owner.id}/#{name}")
    RemoveFileJob.perform_now(owner.id, "#{name};echo harmless")
    expect(path).to exist
    RemoveFileJob.perform_now(owner.id, name)
    expect(path).not_to exist
  end

  it 'requires authentication for private routes' do
    get tool_path(tool)
    expect(response).to redirect_to(new_user_session_path)
    get download_path(file: "#{'a' * 32}.wav")
    expect(response).to redirect_to(new_user_session_path)
    post equalize_path, params: { tool_id: tool.id }
    expect(response).to redirect_to(new_user_session_path)
    patch tool_path(tool), params: { tool: { name: 'changed' } }
    expect(response).to redirect_to(new_user_session_path)
    delete tool_path(tool)
    expect(response).to redirect_to(new_user_session_path)
  end

  it 'prevents another user from viewing, editing, deleting or processing a tool' do
    sign_in other
    expect { get tool_path(tool) }.to raise_error(ActiveRecord::RecordNotFound)
    sign_in other
    expect { patch tool_path(tool), params: { tool: { name: 'changed' } } }
      .to raise_error(ActiveRecord::RecordNotFound)
    sign_in other
    expect { delete tool_path(tool) }.to raise_error(ActiveRecord::RecordNotFound)
    expect(Tool).not_to receive(:equalize)
    sign_in other
    expect { post equalize_path, params: { tool_id: tool.id, direction: 'radio' } }
      .to raise_error(ActiveRecord::RecordNotFound)
    expect(tool.reload.name).to eq('Synthetic tool')
  end

  it 'allows owner reads and updates and restricts the index' do
    sign_in owner
    get tool_path(tool)
    expect(response).to have_http_status(:ok)
    patch tool_path(tool), params: { tool: { name: 'Updated synthetic tool', user_id: other.id } }
    expect(response).to redirect_to(tool_path(tool))
    expect(tool.reload.name).to eq('Updated synthetic tool')
    expect(tool.user_id).to eq(owner.id)
    sign_out owner
    sign_in other
    get tools_path
    expect(response.body).not_to include('Updated synthetic tool')
  end

  it 'allows owner deletion' do
    sign_in owner
    expect { delete tool_path(tool) }.to change(Tool, :count).by(-1)
  end

  it 'rejects invalid uploads and does not invoke conversion' do
    sign_in owner
    expect(Tool).not_to receive(:equalize)
    [nil, 'not an upload', { path: '/etc/hosts' }].each do |file|
      post equalize_path, params: { tool_id: tool.id, direction: 'radio', file: file }
      expect(response).to have_http_status(:unprocessable_entity)
    end
  end

  it 'returns an owner-bound output and schedules owner-bound cleanup' do
    sign_in owner
    previous_adapter = ActiveJob::Base.queue_adapter
    tempfile = Tempfile.new(['synthetic', '.wav'])
    begin
      tempfile.write('synthetic content; converter mocked for request test')
      tempfile.flush
      upload = Rack::Test::UploadedFile.new(tempfile.path, 'audio/wav')
      name = "#{'a' * 32}.wav"
      expect(Tool).to receive(:equalize).with(kind_of(ActionDispatch::Http::UploadedFile), :radio,
                                              user_id: owner.id).and_return(name)
      ActiveJob::Base.queue_adapter = :test
      post equalize_path, params: { tool_id: tool.id, direction: 'radio', file: upload }
      expect(response.parsed_body).to eq('output' => name)
      expect(RemoveFileJob).to have_been_enqueued.with(owner.id, name)
    ensure
      tempfile.close!
      ActiveJob::Base.queue_adapter = previous_adapter
    end
  end

  it 'only downloads the current owner output and rejects traversal' do
    name = "#{'a' * 32}.wav"
    directory = EqualizedAudio.directory(owner.id, create: true)
    directory.join(name).write('synthetic output')
    sign_in owner
    get download_path(file: name)
    expect(response).to have_http_status(:ok)
    expect(response.body).to eq('synthetic output')
    ['../../config/database.yml', "../#{owner.id}/#{name}", '/etc/hosts', '%2e%2e%2fconfig/database.yml'].each do |file|
      get download_path(file: file)
      expect(response).to have_http_status(:not_found)
    end
    sign_out owner
    sign_in other
    get download_path(file: name, id: tool.id)
    expect(response).to have_http_status(:not_found)
    expect { get "/equalized_audio/#{name}" }.to raise_error(ActionController::RoutingError)
  end

  it 'rejects arbitrary public demo partial paths' do
    get demo_path(internal: 'custom')
    expect(response).to have_http_status(:not_found)
    get demo_path(internal: 'layouts/application')
    expect(response).to have_http_status(:not_found)
    get demo_path(internal: 'color_picker')
    expect(response).to have_http_status(:ok)
  end

  it 'rejects cookie-authenticated writes without a CSRF token' do
    sign_in owner
    previous = ActionController::Base.allow_forgery_protection
    ActionController::Base.allow_forgery_protection = true
    begin
      expect { patch tool_path(tool), params: { tool: { name: 'CSRF' } } }
        .to raise_error(ActionController::InvalidAuthenticityToken)
      expect { delete tool_path(tool) }.to raise_error(ActionController::InvalidAuthenticityToken)
      expect { post equalize_path, params: { tool_id: tool.id, direction: 'radio' } }
        .to raise_error(ActionController::InvalidAuthenticityToken)
      expect(tool.reload.name).to eq('Synthetic tool')
      sign_in owner
      get tool_path(tool)
      token = Nokogiri::HTML(response.body).at_css('meta[name="csrf-token"]')['content']
      patch tool_path(tool), params: { tool: { name: 'Valid CSRF' } }, headers: { 'X-CSRF-Token' => token }
      expect(response).to redirect_to(tool_path(tool))
      expect(tool.reload.name).to eq('Valid CSRF')
    ensure
      ActionController::Base.allow_forgery_protection = previous
    end
  end
end

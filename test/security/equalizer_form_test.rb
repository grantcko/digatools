# Standalone rendering regression; no application database is used.
ENV['MT_NO_PLUGINS'] = '1'
gem 'minitest', '~> 5.0'
require 'minitest/autorun'
require 'erb'

module EqualizerFormFixture
  class Tool
    attr_reader :id

    def initialize(id)
      @id = id
    end
  end

  class View
    def initialize(tool)
      @tool = tool
      @eq_directions = [:radio]
    end

    def image_tag(*)
      ''
    end

    def form_authenticity_token
      'synthetic-test-token'
    end

    def hidden_field_tag(name, value)
      %(<input type="hidden" name="#{ERB::Util.html_escape(name)}" value="#{ERB::Util.html_escape(value)}">)
    end

    def render
      template = File.read(File.expand_path('../../app/views/tools/_auto_equalizer.erb', __dir__))
      ERB.new(template).result(binding)
    end
  end
end

class EqualizerFormTest < Minitest::Test
  def test_owned_tool_form_submits_the_tool_id
    html = EqualizerFormFixture::View.new(EqualizerFormFixture::Tool.new(42)).render
    assert_match(/type="hidden" value="42" name="tool_id"/, html)
    assert_match(/name="authenticity_token" value="synthetic-test-token"/, html)
  end

  def test_demo_form_does_not_invent_a_tool_id
    html = EqualizerFormFixture::View.new('auto_equalizer').render
    refute_match(/name="tool_id"/, html)
  end
end

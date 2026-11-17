# frozen_string_literal: true

require 'test_helper'
require 'stringio'

# A transition's own callbacks (transition ..., before:/around:/after:) drawn
# where the core runs them among the machine's callbacks
class BranchCallbacksTest < StateMachines::TestCase
  Introspection = StateMachines::Diagram::Introspection

  def setup
    @machine = Phoenix.state_machines[:flame]
  end

  # What the core ran on firing +event+ from +state+
  def fired(state, event, **attributes)
    phoenix = Phoenix.new
    phoenix.flame = state.to_s
    attributes.each { |name, value| phoenix.public_send(:"#{name}=", value) }
    phoenix.public_send(event)
    phoenix.log
  end

  # The callback sequence as the log writes it: an around under its phase
  def as_log(sequence, ritual: true)
    sequence.reject { !ritual && Introspection.conditional?(it[:conditions]) }
            .map { it[:phase] ? "#{it[:label]} #{it[:phase]}" : it[:label] }
  end

  def sequence(from, to, event)
    branch = Introspection.event_transitions(@machine, @machine.events[event])
                          .find { |source, target, _branch| [source, target] == [from, to] }.last
    Introspection.callback_sequence(@machine, from, to, event, branch: branch)
  end

  def metadata
    StateMachines::Diagram::Builder.new(@machine).tap(&:build).transition_metadata
  end

  def transition(event, from, to)
    metadata.find { [it[:event], it[:from], it[:to]] == [event, from, to] }
  end

  def test_branch_callbacks_run_closest_to_the_state_change
    assert_equal ['stoke', 'channel enter', 'chant', 'gather_heat', 'shield enter', 'shield exit', 'channel exit',
                  'roar', 'scatter_sparks'],
                 fired(:ember, :ignite)
    assert_equal fired(:ember, :ignite), as_log(sequence(:ember, :blaze, :ignite))
  end

  def test_a_conditional_machine_callback_keeps_its_place_and_conditions
    steps = sequence(:ember, :blaze, :ignite)

    assert_equal({ if: %w[ritual?], unless: [] }, steps.find { it[:label] == 'chant' }[:conditions])
    # the branch's callbacks have none of their own: the branch's guards select them
    refute(steps.select { %w[gather_heat shield roar].include?(it[:label]) }
                .any? { Introspection.conditional?(it[:conditions]) })
    assert_equal fired(:ember, :ignite, ritual: false), as_log(steps, ritual: false)
  end

  def test_each_branch_of_an_event_runs_its_own_callbacks
    assert_equal fired(:ash, :rekindle), as_log(sequence(:ash, :ember, :rekindle))
    assert_equal fired(:ash, :rekindle, feathers: 0), as_log(sequence(:ash, :blaze, :rekindle))
    assert_equal fired(:blaze, :rekindle), as_log(sequence(:blaze, :blaze, :rekindle))
  end

  def test_a_state_context_transition_runs_its_callbacks_in_the_order_written
    # around: is written before before:, so smolder wraps dim
    assert_equal ['stoke', 'channel enter', 'chant', 'smolder enter', 'dim', 'smolder exit', 'channel exit',
                  'crumble', 'scatter_sparks'],
                 fired(:blaze, :burn_out)
    assert_equal fired(:blaze, :burn_out), as_log(sequence(:blaze, :ash, :burn_out))
  end

  def test_the_builder_lists_branch_callbacks_with_the_machine_ones
    ignite = transition('ignite', 'ember', 'blaze')

    assert_equal({ before: ['stoke', 'chant (if ritual?)', 'gather_heat'], around: %w[channel shield],
                   after: %w[roar scatter_sparks] }, ignite[:callbacks])
    assert_equal([%w[ash ember], %w[ash blaze], %w[blaze blaze]],
                 metadata.select { it[:event] == 'rekindle' }.map { [it[:from], it[:to]] })
    assert_equal({ before: ['stoke', 'chant (if ritual?)', 'flare'], around: %w[channel],
                   after: %w[erupt scatter_sparks sing] }, transition('rekindle', 'ash', 'blaze')[:callbacks])
    assert_equal({ if: %w[feathers_left?], unless: [] }, transition('rekindle', 'ash', 'ember')[:conditions])
  end

  def test_the_diagram_action_lists_them_in_run_order
    actions = StateMachines::Diagram::Builder.new(@machine).build.transitions.map(&:action)

    assert_includes actions, 'stoke, channel, chant (if ritual?), gather_heat, shield, roar, scatter_sparks'
    assert_includes actions, 'stoke, channel, chant (if ritual?), smolder, dim, crumble, scatter_sparks'
  end

  def test_the_text_renderer_shows_them
    io = StringIO.new
    StateMachines::Diagram::Renderer.draw_machine(@machine, io: io)

    assert_includes io.string, 'ash -> ember [rekindle] (if: feathers_left?) ' \
                               '(action: stoke, channel, chant (if ritual?), hatch, preen, scatter_sparks, sing)'
  end

  def test_a_partial_build_keeps_the_branch_callbacks
    event = @machine.events[:burn_out]
    builder = StateMachines::Diagram::Builder.new(@machine)
    builder.build_branch(event.branches.first, event)

    assert_equal(['stoke', 'channel', 'chant (if ritual?)', 'smolder', 'dim', 'smolder', 'channel', 'crumble',
                  'scatter_sparks'], builder.transition_metadata.first[:callback_sequence].map { it[:text] })
  end
end

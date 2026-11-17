# StateMachines::Diagram

[![CI](https://github.com/state-machines/state_machines-diagram/actions/workflows/ruby.yml/badge.svg?branch=master)](https://github.com/state-machines/state_machines-diagram/actions/workflows/ruby.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-4.0%2B-red.svg)](state_machines-diagram.gemspec)

Builds a [diagram](https://github.com/seuros/diagram-ruby) `Diagrams::StateDiagram`
from a [state_machines](https://github.com/state-machines/state_machines) machine,
and renders it as text, as the diagram gem's JSON or YAML document, or as a
[state-machines-rs](https://github.com/state-machines/state-machines-rs)
`MachineSchema`. [state_machines-mermaid](https://github.com/state-machines/state_machines-mermaid)
draws Mermaid from the same builder.

## Installation

```ruby
gem 'state_machines-diagram'
```

Requiring the gem makes its renderer the one `Machine#draw` uses.

## Quick Start

```ruby
require 'state_machines-diagram'

class Order
  state_machine :status, initial: :pending do
    after_transition to: :shipped, do: :send_notification

    event :process do
      transition pending: :processing, if: :payment_cleared?
    end

    event :ship do
      transition processing: :shipped, unless: %i[on_hold? address_missing?]
    end

    event :cancel do
      transition %i[pending processing] => :cancelled
    end
  end
end

Order.state_machine(:status).draw
```

writes:

```
=== Order status State Machine ===

States:
  - pending [*]
  - processing
  - shipped (O)
  - cancelled (O)

Transitions:
  - pending -> processing [process] (if: payment_cleared?)
  - processing -> shipped [ship] (unless: on_hold?) (unless: address_missing?) (action: send_notification)
  - pending -> cancelled [cancel]
  - processing -> cancelled [cancel]
```

`[*]` marks the initial state, `(O)` a final one (a state no transition leaves).
Each condition is shown on its own: the transition needs every `if:` to pass and
no `unless:` to, as the core requires of an Array condition. State guards
(`if_state:`, `unless_any_state:`, ...) are shown under their kind, with their
requirements together: `(if_any_state: gate=open, alarm=on)`. `action:` lists the
callbacks the core runs on that transition, before, around, then after.

`draw` takes `io:` (default `$stdout`), `format:` and `human_names: true`, which
labels states and events by their human names.

### Parts of a machine

The core draws one state, event or branch through the same renderer. Each shows
the transitions it involves and the states they connect, under a header saying
which part it is:

```ruby
machine = Order.state_machine(:status)

machine.states[:processing].draw(nil)
machine.events[:cancel].draw(nil)
machine.events[:ship].branches.first.draw(nil, machine.events[:ship], [])
```

The first argument is the core's graph slot, which this renderer does not use.

## Formats

```ruby
Order.state_machine(:status).draw(format: :json)
Order.state_machine(:status).draw(format: :yaml)
Order.state_machine(:status).draw(format: :machine_schema)
```

`:json` and `:yaml` write the diagram gem's own document (`type`, `version`,
`checksum`, `data`), so it loads back with a valid checksum:

```ruby
require 'stringio'
require 'yaml'

json = StringIO.new
Order.state_machine(:status).draw(io: json, format: :json)
Diagrams::Base.from_json(json.string) # => #<Diagrams::StateDiagram ...>

yaml = StringIO.new
Order.state_machine(:status).draw(io: yaml, format: :yaml)
Diagrams::Base.from_h(YAML.safe_load(yaml.string)) # => #<Diagrams::StateDiagram ...>
```

What the diagram cannot hold sits beside `data` under `metadata`: each state's
name, label and markers, and each transition's event, structured conditions and
callbacks, in diagram order:

```json
{"event": "ship", "from": "processing", "to": "shipped", "label": "ship",
 "conditions": {"if": [], "unless": ["on_hold?", "address_missing?"]},
 "callbacks": {"before": [], "around": [], "after": ["send_notification"]}}
```

`:machine_schema` describes the whole machine for the state-machines-rs CLI,
each branch's conditions on its transitions (`guards`, `unless`):

```ruby
StateMachines::Diagram::Renderer.machine_schema(Order.state_machine(:status))
# => {name: "Order#status", initial: "pending", states: ["pending", "processing", "shipped", "cancelled"],
#     events: [{name: "process", transitions: [{sources: ["pending"], target: "processing", guards: ["payment_cleared?"]}]},
#              {name: "ship", transitions: [{sources: ["processing"], target: "shipped", unless: ["on_hold?", "address_missing?"]}]},
#              {name: "cancel", transitions: [{sources: ["pending", "processing"], target: "cancelled"}]}]}
```

Any other format raises `ArgumentError`, as does `:machine_schema` for part of a machine.

## The diagram

The builder fills a `Diagrams::StateDiagram` (diagram 0.4+) through the
diagram's own keyword methods. Its elements are immutable `Data` values:

```ruby
builder = StateMachines::Diagram::Builder.new(Order.state_machine(:status))
diagram = builder.build

diagram.transitions[1]
# => #<data Diagrams::Elements::Transition source_state_id="processing", target_state_id="shipped",
#      label="ship", guard="!on_hold? && !address_missing?", action="send_notification">
```

A transition's `guard` is one expression: `if:` terms, negated `unless:` terms
and state guard groups, joined by `&&`. A String condition (code the core
evaluates) is parenthesized when it is more than one term.

Whether a state is initial or final, the structured conditions and the
callbacks are kept by the builder in `state_metadata` (by diagram id) and
`transition_metadata` (in diagram order), not in the diagram:

```ruby
builder.state_metadata['pending']
# => {name: "pending", label: "pending", initial: true, final: false}
builder.transition_metadata[1].slice(:event, :conditions, :callbacks)
# => {event: "ship", conditions: {if: [], unless: ["on_hold?", "address_missing?"]},
#     callbacks: {before: [], around: [], after: ["send_notification"]}}
```

So are names the diagram refuses: a state named `*` (its terminal pseudo-state)
or a blank name gets an escaped id (`%2a`, `%20`), the nil state the id
`nil_state`, and a blank event name leaves the transition's label empty; the
metadata keeps the name (`Builder.state_id(name)` gives the id).

`build_state(state)`, `build_event(event)` and `build_branch(branch, event)`
build the part of the machine the renderer draws for each; `scope` then names
the part (`"State: processing"`), and is nil after `build`.

## Writing a renderer

A renderer is any object with the four methods the core calls. Build with
`Builder`, and take labels from `StateMachines::Diagram::Labels` so text reads
as it does in every other format:

```ruby
module PlantUmlRenderer
  module_function

  def draw_machine(machine, io: $stdout, **options)
    builder = StateMachines::Diagram::Builder.new(machine, options)
    builder.build
    output(builder, io)
  end

  def draw_state(state, _graph, options = {}, io = $stdout)
    builder = StateMachines::Diagram::Builder.new(state.machine, options)
    builder.build_state(state)
    output(builder, io)
  end

  def draw_event(event, _graph, options = {}, io = $stdout)
    builder = StateMachines::Diagram::Builder.new(event.machine, options)
    builder.build_event(event)
    output(builder, io)
  end

  def draw_branch(branch, _graph, event, _valid_states, io = $stdout)
    builder = StateMachines::Diagram::Builder.new(event.machine)
    builder.build_branch(branch, event)
    output(builder, io)
  end

  def output(builder, io)
    diagram = builder.diagram
    io.puts '@startuml'
    io.puts "title #{diagram.title}"
    diagram.states.each do |state|
      io.puts %(state "#{builder.state_metadata.fetch(state.id)[:label]}" as s#{state.id.unpack1('H*')})
    end
    diagram.transitions.each do |transition|
      line = "s#{transition.source_state_id.unpack1('H*')} --> s#{transition.target_state_id.unpack1('H*')}"
      line += " : #{transition.label}" if transition.label
      line += " [#{transition.guard}]" if transition.guard
      io.puts line
    end
    io.puts '@enduml'
    diagram
  end
end

StateMachines::Machine.renderer = PlantUmlRenderer
Order.state_machine(:status).draw
```

`StateMachines::Diagram::Introspection` reads a machine as the core resolves it
(`states_of`, `transition_pairs`, `guard_conditions`, `callback_labels`), for
renderers that need more than the builder keeps.

## Development

```bash
bundle install
bundle exec rake            # tests (padded_cell on CRuby) and RuboCop
bundle exec rake minitest   # tests with plain Minitest
bundle exec ruby -Itest test/builder_test.rb
bundle exec rubocop
```

## Requirements

- Ruby 4.0+
- state_machines 0.300+
- diagram 0.4+

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Changelog

See [CHANGELOG.md](https://github.com/state-machines/state_machines-diagram/blob/master/CHANGELOG.md).

# StateMachines::Diagram - Extensible Core for State Machine Visualization

[![CI](https://github.com/state-machines/state_machines-diagram/actions/workflows/ruby.yml/badge.svg?branch=master)](https://github.com/state-machines/state_machines-diagram/actions/workflows/ruby.yml)
[![License](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE.txt)
[![Ruby](https://img.shields.io/badge/ruby-3.3%2B-red.svg)](state_machines-diagram.gemspec)

An extensible diagram building foundation for the state_machines ecosystem. This gem provides a structured intermediate representation (IR) and adapter framework that enables consistent visualization across multiple output formats.

## Quick Start

```ruby
# 1. Define a state machine using any supported library
require 'state_machines'

class Order
  state_machine :status, initial: :pending do
    state :pending, :processing, :shipped, :cancelled
    
    event :process do
      transition pending: :processing, if: :payment_cleared?
    end
    
    event :ship do
      transition processing: :shipped, action: :send_notification
    end
    
    event :cancel do
      transition [:pending, :processing] => :cancelled
    end
  end
  
  def payment_cleared?
    @payment_cleared ||= false
  end
  
  def send_notification
    puts "Order shipped!"
  end
end

# 2. Generate diagram representation
require 'state_machines-diagram'

# Text format (default)
Order.state_machine(:status).draw
# Output:
# Status: pending → processing [process] (if: payment_cleared?)
# Status: processing → shipped [ship] (action: send_notification)
# Status: pending → cancelled [cancel]
# Status: processing → cancelled [cancel]

# JSON structure  
Order.state_machine(:status).draw(format: :json)
# Output: {"states": [...], "transitions": [...]}

# With specific rendering gem
require 'state_machines-mermaid'
Order.state_machine(:status).draw(format: :mermaid)
# Output:
# stateDiagram-v2
#   pending --> processing : process (if: payment_cleared?)
#   processing --> shipped : ship (action: send_notification)
#   pending --> cancelled : cancel
#   processing --> cancelled : cancel
```

## Architecture

This gem implements a structured data transformation pipeline:

```
StateMachine → Builder → Diagrams::StateDiagram → Renderer → Output
```

### Core Components

#### 1. Intermediate Representation (IR)

The `Diagrams::StateDiagram` IR uses immutable `Dry::Struct` objects to represent state machine structure:

```ruby
# State representation
Diagrams::Elements::State = Dry::Struct do
  attribute :id, Types::Strict::String
  attribute :state_type, Types::StateType  # :initial, :final, :normal
  attribute :name, Types::Strict::String.optional
end

# Transition representation with semantic information
Diagrams::Elements::Transition = Dry::Struct do
  attribute :source_state_id, Types::Strict::String
  attribute :target_state_id, Types::Strict::String
  attribute :label, Types::Strict::String.optional
  attribute :guard, Types::Strict::String.optional    # if: condition
  attribute :action, Types::Strict::String.optional   # callback method
end

# Complete diagram structure
Diagrams::StateDiagram = Dry::Struct do
  attribute :states, Types::Array.of(Diagrams::Elements::State)
  attribute :transitions, Types::Array.of(Diagrams::Elements::Transition)
  attribute :title, Types::Strict::String.optional
end
```

#### 2. Builder Contract

The `StateMachines::Diagram::Builder` extracts semantic information from state machines:

```ruby
# Core building method
diagram = StateMachines::Diagram::Builder.build_state_diagram(machine, options)

# Builder handles:
# - State extraction with type detection
# - Transition mapping with guard conditions  
# - Callback extraction (before/after/around)
# - Event-to-transition resolution
# - Filtering (state_filter, event_filter)
```

#### 3. Renderer Interface

Renderers implement a standardized contract:

```ruby
module StateMachines::Diagram::Renderer
  # Required method for all renderers
  def self.draw_machine(machine, io: $stdout, **options)
    diagram = build_state_diagram(machine, options)
    output_diagram(diagram, io, options)
  end
  
  private
  
  # Override this method for custom output
  def self.output_diagram(diagram, io, options)
    # Your rendering logic here
  end
end
```

## Error Handling

The gem provides robust error handling for common edge cases:

```ruby
begin
  diagram = StateMachines::Diagram::Builder.build_state_diagram(machine)
rescue StateMachines::Diagram::InvalidStateError => e
  puts "Invalid state configuration: #{e.message}"
rescue StateMachines::Diagram::TransitionError => e
  puts "Transition error: #{e.message}"
end

# Validate diagram structure
if diagram.states.empty?
  raise StateMachines::Diagram::EmptyDiagramError, "No states found"
end
```

## Advanced Usage

### Custom Renderer Example

```ruby
module MyPlantUMLRenderer
  extend StateMachines::Diagram::Renderer
  
  private
  
  def self.output_diagram(diagram, io, options)
    io.puts "@startuml"
    io.puts "title #{diagram.title}" if diagram.title
    
    diagram.states.each do |state|
      io.puts "state #{state.id}"
    end
    
    diagram.transitions.each do |transition|
      line = "#{transition.source_state_id} --> #{transition.target_state_id}"
      line += " : #{transition.label}" if transition.label
      
      annotations = []
      annotations << "#{transition.guard}" if transition.guard  
      annotations << "#{transition.action}" if transition.action
      line += " [#{annotations.join(', ')}]" unless annotations.empty?
      
      io.puts line
    end
    
    io.puts "@enduml"
  end
end

# Use the custom renderer
StateMachines::Machine.renderer = MyPlantUMLRenderer
Order.state_machine(:status).draw
```

### Complex State Machine Support

```ruby
class Dragon
  # Multiple parallel state machines
  state_machine :mood, initial: :sleeping do
    state :sleeping, :hunting, :hoarding
    
    event :wake_up do
      transition sleeping: :hunting, if: :hungry?
      transition sleeping: :hoarding, unless: :hungry?
    end
    
    event :find_treasure do
      transition hoarding: :hoarding  # Self-transition
    end
  end
  
  state_machine :flight, initial: :grounded do
    state :grounded, :airborne
    
    event :take_off do
      transition grounded: :airborne, action: :spread_wings
    end
  end
  
  def hungry?
    @hunger_level > 5
  end
  
  def spread_wings
    puts "Dragon spreads mighty wings!"
  end
end

# Generate diagrams for each state machine
Dragon.state_machine(:mood).draw(show_conditions: true)
Dragon.state_machine(:flight).draw(show_callbacks: true)
```

### Filtering and Options

```ruby
# Focus on specific state
Order.state_machine(:status).draw(state_filter: :processing)

# Focus on specific event  
Order.state_machine(:status).draw(event_filter: :ship)

# Show semantic information
Order.state_machine(:status).draw(show_conditions: true, show_callbacks: true)

# Human-readable names
Order.state_machine(:status).draw(human_names: true)

# Output to file
File.open('order_diagram.json', 'w') do |file|
  Order.state_machine(:status).draw(io: file, format: :json)
end
```

## Testing Strategy

The gem includes comprehensive test coverage with robust fixtures:

```bash
# Run all tests
rake test

# Test specific components
ruby -Itest test/unit/builder_test.rb
ruby -Itest test/unit/renderer_test.rb

# Lint code
bundle exec rubocop
```

### Test Coverage

- **Builder Tests**: State extraction, transition mapping, guard condition handling
- **Renderer Tests**: Output format validation, option handling, error cases
- **Integration Tests**: End-to-end workflows with complex state machines
- **Edge Case Tests**: Invalid states, circular transitions, missing callbacks

## Ecosystem Integration

This gem serves as the foundation for rendering-specific gems:

- **`state_machines-diagram`** (this gem): Core diagram building and IR
- **`state_machines-mermaid`**: Mermaid syntax renderer
- **`state_machines-graphviz`**: GraphViz DOT format renderer (planned)
- **Custom renderers**: PlantUML, SVG, ASCII art, etc.

### Supported State Machine Libraries

- `state_machines` (primary)
- `state_machines-activerecord`
- `state_machines-activemodel`

### Ruby Version Support

- **Ruby 3.3+**: Required for pattern matching and modern syntax
- **Rails 7.2+**: Optional, for ActiveRecord/ActiveModel integration

## Performance Considerations

- **Immutable IR**: Uses `Dry::Struct` for thread-safe, immutable diagram objects
- **Lazy Evaluation**: Diagrams are built only when `draw` is called
- **Memory Efficient**: No global state or caching by default
- **Streaming Support**: Large diagrams can be rendered incrementally

## Contributing

1. Fork the repository
2. Create a feature branch (`git checkout -b my-new-feature`)
3. Add tests for your changes
4. Ensure all tests pass (`rake test`)
5. Ensure code style compliance (`bundle exec rubocop`)
6. Submit a pull request

### Adding a New State Machine Library

To support a new state machine library, implement the builder pattern:

```ruby
module StateMachines::Diagram::Adapters
  class MyLibraryAdapter
    def initialize(machine)
      @machine = machine
    end
    
    def build_states
      # Extract states from @machine
    end
    
    def build_transitions  
      # Extract transitions from @machine
    end
  end
end
```

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Changelog

See [CHANGELOG.md](CHANGELOG.md) for version history and breaking changes.

# frozen_string_literal: true

require 'state_machines'
require 'state_machines/diagram/version'
require 'state_machines/diagram/builder'
require 'state_machines/diagram/renderer'

# Loading the gem changes no global state. Machine#draw (and State, Event
# and Branch#draw) use this renderer once it is chosen:
#
#   StateMachines::Machine.renderer = StateMachines::Diagram::Renderer
#
# or draw with it directly: StateMachines::Diagram::Renderer.draw_machine(machine)

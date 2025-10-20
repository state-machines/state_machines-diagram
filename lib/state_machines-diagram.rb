# frozen_string_literal: true

require 'state_machines'
require 'state_machines/diagram/version'
require 'state_machines/diagram/builder'
require 'state_machines/diagram/renderer'

# Set the renderer to use diagram
StateMachines::Machine.renderer = StateMachines::Diagram::Renderer

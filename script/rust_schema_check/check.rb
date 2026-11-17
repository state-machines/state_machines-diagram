# frozen_string_literal: true

# Reads the MachineSchema SchemaBuilder writes for every test fixture back
# through state-machines-rs (state-machines-core's own types, validation and
# MachineSchema::transition_callbacks) and checks that generated code would
# run, on every transition, the callbacks the core runs, in its order.
#
# Needs cargo and a state-machines-rs checkout, so it is not part of the
# default rake task:
#
#   STATE_MACHINES_RS=../state-machines-rs bundle exec rake rust_schema_check
#
# CARGO_TARGET_DIR is honoured (default: tmp/rust_schema_check/target).

require 'json'
require 'fileutils'
require 'open3'
require 'state_machines-diagram'

StateMachines::Machine.ignore_method_conflicts = true
root = File.expand_path('../..', __dir__)
Dir[File.join(root, 'test/models/*.rb')].each { require it }

module RustSchemaCheck
  Introspection = StateMachines::Diagram::Introspection

  # A machine beside the fixtures whose callback placement differs: branch
  # callbacks with machine ones (including a branch after, which keeps the
  # machine's afters on each transition), a loopback callback, a state's
  # block transition
  class Lantern
    attr_accessor :state

    state_machine :state, initial: :dark do
      before_transition :trim
      around_transition :shield
      after_transition :log
      after_transition from: :lit, to: same, do: :flicker
      event :light do
        transition dark: :lit, if: :oil?, around: :strike, after: :glow
        transition dark: :smoking, before: :scrape
      end
      event(:fan) { transition lit: same, after: :sway }
      event(:snuff) { transition %i[lit smoking] => :dark }
      state(:smoking) { transition to: :dark, on: :douse, around: :cover, before: :wet }
    end
  end

  # How generated code runs a merged callbacks list (CallbackKind docs)
  def self.generated_order(callbacks)
    afters, entered = callbacks.partition { |kind, _name| kind == 'after' }
    entered = entered.map { |kind, name| [kind, kind == 'around' ? 'enter' : nil, name] }
    exits = entered.select { it[1] == 'enter' }.reverse.map { [it[0], 'exit', it[2]] }
    entered + exits + afters.map { |_kind, name| ['after', nil, name] }
  end

  # The core's order on each transition, keyed as the Rust side prints it
  def self.core_orders(machine)
    machine.events.flat_map do |event|
      Introspection.event_transitions(machine, event).map do |from, to, branch|
        conditions = Introspection.guard_conditions(branch)
        guards = conditions[:if] + conditions.except(:if, :unless).map do |kind, value|
          StateMachines::Diagram::Labels.state_guard_token(kind, value)
        end
        key = [event.name.to_s, StateMachines::Diagram::Builder.state_id(from),
               StateMachines::Diagram::Builder.state_id(to), guards, conditions[:unless]]
        sequence = Introspection.callback_sequence(machine, from, to, event.name, branch: branch)
        [key, sequence.map { [it[:kind].to_s, it[:phase]&.to_s, it[:label]] }]
      end
    end.to_h
  end
end

rs = File.expand_path(ENV.fetch('STATE_MACHINES_RS', File.join(root, '../state-machines-rs')))
abort "no state-machines-rs checkout at #{rs} (set STATE_MACHINES_RS)" unless File.directory?(rs)
work = File.join(root, 'tmp/rust_schema_check')
FileUtils.mkdir_p(File.join(work, 'src'))
FileUtils.mkdir_p(File.join(work, 'schemas'))
File.write(File.join(work, 'Cargo.toml'), <<~TOML)
  [package]
  name = "rust-schema-check"
  version = "0.0.0"
  edition = "2024"
  publish = false

  [dependencies]
  state-machines-core = { path = #{File.join(rs, 'state-machines-core').to_json}, features = ["std"] }

  [workspace]
TOML
FileUtils.cp(File.join(__dir__, 'main.rs'), File.join(work, 'src/main.rs'))
target = ENV.fetch('CARGO_TARGET_DIR', File.join(work, 'target'))
system({ 'CARGO_TARGET_DIR' => target }, 'cargo', 'build', '-q', '--manifest-path', File.join(work, 'Cargo.toml'),
       exception: true)

owners = [Dragon, Mage, Troll, Regiment, Battle, Character, Commander, Phoenix, RustSchemaCheck::Lantern]
# The fixture machines SchemaBuilder must refuse, and why; any other refusal,
# or one of these not happening, fails the check
expected_refusals = { 'Phoenix#flame' => 'cannot express the conditional callback chant (if ritual?)' }
failures = []
machines = {}
refused = []
owners.each do |owner|
  owner.state_machines.each_value do |machine|
    name = "#{owner.name.split('::').last}##{machine.name}"
    path = File.join(work, 'schemas', "#{owner.name.split('::').last}_#{machine.name}.json")
    begin
      File.write(path, StateMachines::Diagram::SchemaBuilder.new(machine).to_json)
      machines[path] = [name, machine]
    rescue ArgumentError => e
      reason = expected_refusals[name]
      next failures << "#{name}: unexpected refusal: #{e.message}" unless reason && e.message.include?(reason)

      refused << name
      puts "refused  #{name}: #{e.message}"
    end
  end
end
(expected_refusals.keys - refused).each { failures << "#{it}: expected a refusal (#{expected_refusals[it]}), none" }
abort "no schema exported\n#{failures.join("\n")}" if machines.empty?

output, status = Open3.capture2(File.join(target, 'debug/rust-schema-check'), *machines.keys)
abort 'rust-schema-check failed' unless status.success?

reports = output.each_line.map { JSON.parse(it) }
missing = machines.keys - reports.map { it['file'] }
missing.each { failures << "#{machines[it].first}: no report from Rust" }
reports.each do |report|
  name, machine = machines.fetch(report['file'])
  problems = [report['parse_error'], *report['errors']].compact
  expected = RustSchemaCheck.core_orders(machine)
  seen = report.fetch('edges', []).map do |edge|
    key = edge.values_at('event', 'source', 'target', 'guards', 'unless')
    generated = RustSchemaCheck.generated_order(edge['callbacks'])
    if expected[key] != generated
      problems << "#{key.first(3).join(' ')}: core runs #{expected[key].inspect}, rs #{generated.inspect}"
    end
    key
  end
  (expected.keys - seen).each { problems << "#{it.first(3).join(' ')}: missing from the schema" }
  failures << "#{name}: #{problems.join('; ')}" if problems.any?
  puts(problems.empty? ? "ok       #{name} (#{seen.size} transitions)" : "FAILED   #{name}")
end
puts "#{reports.size} of #{machines.size} exported schemas reported by Rust"
abort "FAILED\n#{failures.join("\n")}" if failures.any? || reports.size != machines.size

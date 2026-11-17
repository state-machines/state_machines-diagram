//! Reads each MachineSchema JSON file given as it is written, through
//! state-machines-core, and prints one JSON line per file: the validation
//! errors, and for every transition source the callbacks generated code
//! merges for it (MachineSchema::transition_callbacks), in that order.
use state_machines_core::schema::{DiagnosticLevel, MachineSchema};
use state_machines_core::serde_json::{self, json};

fn main() -> Result<(), Box<dyn std::error::Error>> {
    for path in std::env::args().skip(1) {
        let schema: MachineSchema = match serde_json::from_str(&std::fs::read_to_string(&path)?) {
            Ok(schema) => schema,
            Err(error) => {
                println!("{}", json!({ "file": path, "parse_error": error.to_string() }));
                continue;
            }
        };
        let errors: Vec<String> = schema
            .validate()
            .into_iter()
            .filter(|d| d.level == DiagnosticLevel::Error)
            .map(|d| d.message)
            .collect();
        let mut edges = Vec::new();
        for event in &schema.events {
            for transition in &event.transitions {
                for source in &transition.sources {
                    let callbacks: Vec<_> = schema
                        .transition_callbacks(event, transition, source, &transition.target)
                        .iter()
                        .map(|c| json!([c.kind.as_str(), c.name]))
                        .collect();
                    edges.push(json!({
                        "event": event.name, "source": source, "target": transition.target,
                        "guards": transition.guards, "unless": transition.unless, "callbacks": callbacks
                    }));
                }
            }
        }
        println!("{}", json!({ "file": path, "errors": errors, "edges": edges }));
    }
    Ok(())
}

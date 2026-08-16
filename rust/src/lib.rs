mod battery;
mod fitting;
mod licence;
mod log_reader;
mod motor;
mod plausibility;
mod powertrain;
mod propeller;

use godot::prelude::*;

struct LothalCore;

#[gdextension]
unsafe impl ExtensionLibrary for LothalCore {
    // One builder for the whole crate. All registered classes follow.
}

// The hello-world probes (Hello::hello / forty_two / make_observables) that proved gdext's
// static-func and GDScript-instantiation behaviour lived here through the port. They are gone:
// they shipped in the release dylib, added three more registered names to a binary whose whole
// purpose is to expose fewer, and carried four .expect() calls that abort the process under
// `panic = "abort"` if observables.gd ever moves. What they established is recorded in the plan,
// which is where a finished probe belongs.

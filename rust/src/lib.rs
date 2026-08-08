mod motor;
mod propeller;

use godot::prelude::*;

struct LothalCore;

#[gdextension]
unsafe impl ExtensionLibrary for LothalCore {
    // One builder for the whole crate. All registered classes follow.
}

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct Hello;

#[godot_api]
impl Hello {
    #[func]
    fn create() -> Gd<Self> {
        Gd::from_object(Self)
    }

    #[func]
    fn hello(&self) -> i32 {
        42
    }

    // PROBE 2 (static funcs) — design §6.6 claims `PropellerModel.fit_k_t(...)` works as a
    // class-level call. If gdext 0.5 has no receiver-less #[func], `Hello.forty_two()` from
    // GDScript errors and Task 3 uses the GDScript-shim fallback.
    #[func]
    fn forty_two(&self) -> i32 {
        42
    }

    // PROBE 3 (instantiate a GDScript class from Rust) — Task 5 needs Rust Powertrain to
    // create an Observables. Loads res://src/sim/observables.gd and instantiates it.
    #[func]
    fn make_observables(&self) -> Gd<godot::classes::RefCounted> {
        let mut loader = godot::classes::ResourceLoader::singleton();
        let resource = loader
            .load("res://src/sim/observables.gd")
            .expect("observables.gd should load");
        let mut script: Gd<godot::classes::GDScript> = resource
            .try_cast::<godot::classes::GDScript>()
            .expect("loaded resource should be a GDScript");
        script
            .instantiate(&[])
            .try_to::<Gd<godot::classes::RefCounted>>()
            .expect("instantiated script should be a RefCounted")
    }
}

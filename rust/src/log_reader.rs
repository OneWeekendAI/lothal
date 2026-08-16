//! Reading a flight log's ROWS (LTHL-55).
//!
//! ===========================================================================
//! WHY THIS IS IN THE NATIVE CORE
//! ===========================================================================
//!
//! A three-minute log is about 180 000 rows of 55 columns — roughly ten million float parses of
//! round-tripped scientific notation. GDScript does that in seconds, on the main thread, every
//! time a builder clicks a different flight, which is the difference between a room that feels
//! like a tool and a room that feels like a wait.
//!
//! Only the PARSE is here. Min/max decimation for drawing lives in TraceView, in GDScript, and
//! deliberately: the bucket count is the widget's pixel width, which changes every time the
//! window is resized. Decimating here would mean re-reading a 197 MB file to resize a window,
//! while decimating there is a pass over floats already in memory.
//!
//! ===========================================================================
//! panic = "abort", AND WHAT THAT MEANS FOR EVERY LINE BELOW
//! ===========================================================================
//!
//! The crate aborts on panic, because a panic across the FFI boundary is undefined behaviour.
//! So a single `unwrap()` in this file takes the whole application down while a builder is
//! browsing their flights.
//!
//! That matters more here than anywhere else in the crate. Every other Rust entry point is fed
//! by Lothal's own code; this one is fed by a file on disk that a builder may have truncated by
//! closing the laptop mid-write, edited by hand, or copied from someone else.
//!
//! There is already a house rule for exactly this, in src/lab/json_store.gd: a bad file is a
//! warning and a defaulted result, never a crash. Every path below returns `ok: false` with a
//! reason a human can read. THERE IS NO unwrap, NO expect, AND NO INDEXING BY [] IN THIS FILE.
//!
//! ===========================================================================
//! A LOG NAMES AN AIRCRAFT; IT DOES NOT DEFINE ONE
//! ===========================================================================
//!
//! src/sim/flight_recorder.gd's header states the rule and the GDScript test suite enforces it by
//! grepping every reader's source. This file is a reader. It returns numbers and strings, knows
//! nothing about builds or parts, and must never learn.

use godot::prelude::*;

/// A cell that will not parse. NaN rather than zero, because zero is a PLAUSIBLE READING and NaN
/// is not: a trace with a silent zero in it looks like a moment the aircraft was still, while a
/// NaN is visibly absent and the drawing code skips it. Counted in `bad_cells` either way, so the
/// caller can say how much of the file did not survive.
const UNPARSEABLE: f64 = f64::NAN;

#[derive(GodotClass)]
#[class(no_init, base=RefCounted)]
pub struct LogReader;

#[godot_api]
impl LogReader {
    /// Reads the named columns out of a Lothal flight log.
    ///
    /// Returns a Dictionary, always, and never fails loudly:
    ///
    /// ```text
    /// {
    ///   "ok":        bool,
    ///   "reason":    String,   // "" when ok
    ///   "rows":      int,
    ///   "bad_cells": int,
    ///   "columns":   { name: PackedFloat64Array, ... },
    /// }
    /// ```
    ///
    /// ONLY THE REQUESTED COLUMNS ARE PARSED, and that is the point of taking names rather than
    /// returning everything. The cells of unwanted columns are still SPLIT — the commas have to be
    /// found either way — but they are never turned into floats.
    ///
    /// The saving is real and it is not the twenty-seven-fold one an early comment here claimed:
    /// measured on a 2000-row fixture, two columns cost ~1400 us against ~3350 us for all 55.
    /// Better than two-to-one, because splitting is shared work and only parsing is skipped.
    ///
    /// A name that is not in the file is not an error. It comes back absent from `columns`, so a
    /// caller asking for a column that a pre-LTHL-52 log does not carry gets a shorter dictionary
    /// rather than a failure — which is what lets Studio open old logs with no special cases.
    #[func]
    fn read_columns(path: GString, names: PackedStringArray) -> VarDictionary {
        let absolute = godot::classes::ProjectSettings::singleton().globalize_path(&path);
        let text = match std::fs::read_to_string(absolute.to_string()) {
            Ok(t) => t,
            Err(e) => return Self::failure(&format!("cannot read {path}: {e}")),
        };

        let mut lines = text.lines();

        // Line 1 is the '#'-prefixed JSON header. Skipped, not parsed: read_header() in GDScript
        // owns that and there must not be a second parser for it.
        let first = match lines.next() {
            Some(l) => l,
            None => return Self::failure("the file is empty"),
        };
        if !first.starts_with('#') {
            return Self::failure("no flight-log header line");
        }

        let header_row = match lines.next() {
            Some(l) => l,
            None => return Self::failure("the file has a header but no columns"),
        };
        let column_names: Vec<&str> = header_row.split(',').map(str::trim).collect();

        // Which physical column each requested name sits at, and where it lands in the output.
        // Built once, before the row loop, so the inner loop is an integer comparison rather
        // than a string search per cell.
        let mut wanted: Vec<(usize, String)> = Vec::new();
        for name in names.as_slice() {
            let name = name.to_string();
            if let Some(index) = column_names.iter().position(|c| *c == name) {
                wanted.push((index, name));
            }
        }
        wanted.sort_by_key(|(index, _)| *index);

        let mut series: Vec<Vec<f64>> = vec![Vec::new(); wanted.len()];
        let mut rows: i64 = 0;
        let mut bad_cells: i64 = 0;
        let mut stopped: Option<String> = None;

        for (line_number, line) in lines.enumerate() {
            if line.trim().is_empty() {
                continue;
            }

            // A SHORT ROW ENDS THE READ RATHER THAN BEING PADDED. This is the shape a log
            // truncated mid-write actually takes — the last line is half a row — and padding it
            // would invent samples the flight never produced, at the exact end of the file where
            // a builder is most likely to be looking for what went wrong.
            //
            // Counted by scanning for commas rather than by collecting the cells into a Vec. The
            // Vec was the first version and it cost more than the parsing it was feeding: one
            // 55-element allocation per row, which swamped much of the saving from asking for two
            // columns instead of fifty-five. Measured on a 2000-row fixture: two columns went from
            // 1735 us to ~1400 us, against ~3350 us for all 55. Worth stating honestly — dropping
            // the Vec bought about 20%, not an order of magnitude, because the SPLIT itself is
            // unavoidable (the commas have to be found either way) and only the PARSE is skipped.
            let cell_count = line.bytes().filter(|b| *b == b',').count() + 1;
            if cell_count != column_names.len() {
                stopped = Some(format!(
                    "row {} has {} cells, not {} — file truncated? {} rows read",
                    line_number + 1,
                    cell_count,
                    column_names.len(),
                    rows
                ));
                break;
            }

            // One pass over the row's cells, parsing only the wanted ones. `wanted` is sorted by
            // column index, so `slot` walks forward with the split and never searches.
            let mut slot = 0usize;
            for (index, raw) in line.split(',').enumerate() {
                let want = match wanted.get(slot) {
                    Some((i, _)) if *i == index => true,
                    Some(_) => false,
                    None => break, // every requested column is behind us
                };
                if !want {
                    continue;
                }
                match raw.trim().parse::<f64>() {
                    Ok(value) => Self::push(&mut series, slot, value),
                    Err(_) => {
                        bad_cells += 1;
                        Self::push(&mut series, slot, UNPARSEABLE);
                    }
                }
                slot += 1;
            }
            rows += 1;
        }

        let mut columns = VarDictionary::new();
        for (slot, (_, name)) in wanted.iter().enumerate() {
            let packed: PackedFloat64Array = match series.get(slot) {
                Some(values) => values.as_slice().into(),
                None => PackedFloat64Array::new(),
            };
            columns.set(name.clone(), &packed);
        }

        let mut out = VarDictionary::new();
        // A TRUNCATED FILE IS STILL A SUCCESSFUL READ of the rows that were there, and says so in
        // the reason. Returning ok: false would throw away a flight's worth of good data because
        // its last line was half written, which is the opposite of useful when the truncation
        // happened because the app died during the flight worth looking at.
        out.set("ok", true);
        out.set("reason", stopped.unwrap_or_default());
        out.set("rows", rows);
        out.set("bad_cells", bad_cells);
        out.set("columns", &columns);
        out
    }

    /// Growth without indexing. `series` is sized from `wanted` and `slot` comes from enumerating
    /// the same vector, so the miss is unreachable — but this file has no `[]` in it, and an
    /// unreachable branch that returns is cheaper than an invariant someone has to trust.
    fn push(series: &mut [Vec<f64>], slot: usize, value: f64) {
        if let Some(column) = series.get_mut(slot) {
            column.push(value);
        }
    }

    fn failure(reason: &str) -> VarDictionary {
        let mut out = VarDictionary::new();
        out.set("ok", false);
        out.set("reason", reason.to_string());
        out.set("rows", 0i64);
        out.set("bad_cells", 0i64);
        out.set("columns", &VarDictionary::new());
        out
    }
}

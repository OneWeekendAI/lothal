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
        // DUPLICATES ARE DROPPED, and the reason is not tidiness. `slot` below walks forward
        // through this vector as the split walks forward through the row, which requires the
        // indices to be strictly increasing. Two entries at the same index stall the walk: the
        // first matches, `slot` advances to the second, and the second's index is now BEHIND the
        // cell being looked at, so it never matches and every later column comes back empty.
        //
        // Found by FlightAnalysis asking for gyro_x_rad_s twice — once as the spectrum channel
        // and once as the roll axis — which is a completely reasonable thing for a caller to do
        // and produced a silent empty column rather than an error.
        let mut wanted: Vec<(usize, String)> = Vec::new();
        for name in names.as_slice() {
            let name = name.to_string();
            if wanted.iter().any(|(_, existing)| *existing == name) {
                continue;
            }
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

    /// The averaged magnitude spectrum of one channel (LTHL-20).
    ///
    /// ```text
    /// {
    ///   "ok":        bool,
    ///   "reason":    String,   // "" when ok
    ///   "bin_hz":    float,    // fs / frame_len — the frequency resolution
    ///   "frame_len": int,
    ///   "hop":       int,
    ///   "frames":    int,      // frames actually averaged
    ///   "skipped":   int,      // frames dropped for containing an unreadable sample
    ///   "mags":      PackedFloat64Array,
    /// }
    /// ```
    ///
    /// TAKES SAMPLES, NOT A PATH, and that is deliberate. `read_columns` has already parsed the
    /// file and GDScript is holding the floats; re-reading 197 MB to compute a transform over
    /// numbers already in memory would be the expensive half of this feature done twice. It also
    /// leaves this function pure arithmetic, which is what lets the crosscheck feed it the same
    /// array Python was fed rather than trusting two readers to agree first.
    ///
    /// Frequencies are not returned. Bin `i` is at `i * bin_hz`, and shipping a second array of
    /// 512 floats that the caller can compute from one is a second spelling of the x axis.
    #[func]
    fn spectrum(samples: PackedFloat64Array, sample_rate_hz: f64) -> VarDictionary {
        match crate::spectrum::averaged(samples.as_slice(), sample_rate_hz) {
            Ok(s) => {
                let mags: PackedFloat64Array = s.mags.as_slice().into();
                let mut out = VarDictionary::new();
                out.set("ok", true);
                out.set("reason", String::new());
                out.set("bin_hz", sample_rate_hz / (s.frame_len as f64));
                out.set("frame_len", s.frame_len as i64);
                out.set("hop", s.hop as i64);
                out.set("frames", s.frames as i64);
                out.set("skipped", s.skipped as i64);
                out.set("mags", &mags);
                out
            }
            Err(reason) => {
                let mut out = VarDictionary::new();
                out.set("ok", false);
                out.set("reason", reason);
                out.set("bin_hz", 0.0);
                out.set("frame_len", 0i64);
                out.set("hop", 0i64);
                out.set("frames", 0i64);
                out.set("skipped", 0i64);
                out.set("mags", &PackedFloat64Array::new());
                out
            }
        }
    }

    /// Mean, spread and step spread of one channel, optionally of the DIFFERENCE between two.
    ///
    /// ```text
    /// { "n": int, "mean": float, "sd": float, "step_sd": float, "min": float, "max": float }
    /// ```
    ///
    /// `subtract` may be empty, in which case the statistics are of `samples` alone. When it is
    /// not, the statistics are of `samples[i] - subtract[i]` over the overlapping length, which
    /// is how Studio gets the SENSOR-ONLY excursion: gyro minus omega is what the flight
    /// controller saw that the aircraft was not doing.
    ///
    /// `sd` is the population deviation (divide by n), matching `np.std`'s default and the
    /// `sqrt(sum / n)` in RateTune.vibration_step_noise_rad_s. `step_sd` is the same statistic on
    /// successive differences, which is the one a D gain multiplies.
    ///
    /// NON-FINITE SAMPLES ARE SKIPPED, and a step across a skipped sample is not counted — the
    /// gap between rows 4 and 6 is not a step, and treating it as one would report a difference
    /// accumulated over two intervals as if it happened in one.
    ///
    /// Here rather than in GDScript because it is the same 180 000-row pass the parse was moved
    /// out of. Six channels of it per click, in GDScript, is the wait this whole file exists to
    /// avoid, and it would arrive right after the wait had been removed.
    #[func]
    fn stats(samples: PackedFloat64Array, subtract: PackedFloat64Array) -> VarDictionary {
        let a = samples.as_slice();
        let b = subtract.as_slice();
        let len = if b.is_empty() { a.len() } else { a.len().min(b.len()) };

        // WELFORD, NOT sum_sq/n - mean^2, AND THE DIFFERENCE IS NOT ACADEMIC HERE.
        //
        // The naive formula subtracts two nearly equal large numbers. On an rpm channel sitting
        // at 1234.5678, sum_sq/n is about 1.5e6 and so is mean^2, so the difference keeps about
        // five of the sixteen digits — measured, before this was changed: a channel of 500
        // identical values reported a standard deviation of 1.2e-4 instead of zero.
        //
        // That is small next to an rpm, and it is NOT small next to a gyro noise floor, which is
        // the other thing this function is asked about and which lives around 1e-3 rad/s. A
        // spurious 1e-4 there is a tenth of the answer. Welford accumulates the deviation
        // directly and never forms the large intermediate.
        let mut n = 0usize;
        let mut mean_acc = 0.0f64;
        let mut m2 = 0.0f64;
        let mut lo = f64::INFINITY;
        let mut hi = f64::NEG_INFINITY;

        let mut steps = 0usize;
        let mut step_sum_sq = 0.0f64;
        let mut previous: Option<f64> = None;

        for i in 0..len {
            let value = match (a.get(i), b.get(i)) {
                (Some(x), Some(y)) => x - y,
                (Some(x), None) if b.is_empty() => *x,
                _ => break,
            };
            if !value.is_finite() {
                previous = None;
                continue;
            }
            n += 1;
            let delta = value - mean_acc;
            mean_acc += delta / (n as f64);
            m2 += delta * (value - mean_acc);
            if value < lo {
                lo = value;
            }
            if value > hi {
                hi = value;
            }
            if let Some(p) = previous {
                let step = value - p;
                steps += 1;
                step_sum_sq += step * step;
            }
            previous = Some(value);
        }

        let mut out = VarDictionary::new();
        out.set("n", n as i64);
        if n == 0 {
            out.set("mean", 0.0);
            out.set("sd", 0.0);
            out.set("step_sd", 0.0);
            out.set("min", 0.0);
            out.set("max", 0.0);
            return out;
        }
        // max(0) is belt and braces: Welford's m2 is a sum of products that share a sign and
        // cannot go negative, but a dead-still axis reporting NaN noise would be read as a broken
        // sensor rather than as a still one, and that is not a failure worth risking to save a
        // comparison.
        let variance = (m2 / (n as f64)).max(0.0);
        out.set("mean", mean_acc);
        out.set("sd", variance.sqrt());
        out.set(
            "step_sd",
            if steps == 0 {
                0.0
            } else {
                (step_sum_sq / (steps as f64)).sqrt()
            },
        );
        out.set("min", lo);
        out.set("max", hi);
        out
    }

    /// Per-frame minimum and maximum over the same frame grid the spectrum uses.
    ///
    /// ```text
    /// { "lo": PackedFloat64Array, "hi": PackedFloat64Array }   // one entry per frame
    /// ```
    ///
    /// Studio's admissibility check asks how far the rpm line moves WITHIN one analysis frame.
    /// That is a min/max over each frame of the rpm channel, on the grid `frame_layout` returns,
    /// and it must be the same grid or the check describes a window nothing was measured in.
    ///
    /// A frame containing a non-finite sample yields NaN for that frame rather than being
    /// silently narrowed to its readable part — a smear measured over half a frame is not the
    /// smear over the frame.
    #[func]
    fn frame_extents(
        samples: PackedFloat64Array,
        frame_len: i64,
        hop: i64,
    ) -> VarDictionary {
        let values = samples.as_slice();
        let n = if frame_len <= 0 { 0usize } else { frame_len as usize };
        let step = if hop <= 0 { 1usize } else { hop as usize };

        let mut lo_out: Vec<f64> = Vec::new();
        let mut hi_out: Vec<f64> = Vec::new();
        if n > 0 && values.len() >= n {
            let frames = (values.len() - n) / step + 1;
            for frame in 0..frames {
                let start = frame * step;
                let slice = match values.get(start..start + n) {
                    Some(s) => s,
                    None => break,
                };
                if slice.iter().any(|v| !v.is_finite()) {
                    lo_out.push(f64::NAN);
                    hi_out.push(f64::NAN);
                    continue;
                }
                let mut lo = f64::INFINITY;
                let mut hi = f64::NEG_INFINITY;
                for v in slice {
                    if *v < lo {
                        lo = *v;
                    }
                    if *v > hi {
                        hi = *v;
                    }
                }
                lo_out.push(lo);
                hi_out.push(hi);
            }
        }

        let lo_packed: PackedFloat64Array = lo_out.as_slice().into();
        let hi_packed: PackedFloat64Array = hi_out.as_slice().into();
        let mut out = VarDictionary::new();
        out.set("lo", &lo_packed);
        out.set("hi", &hi_packed);
        out
    }

    /// The frame layout a trace of this length would get, without doing the transform.
    ///
    /// Studio needs it before it has a spectrum: the admissibility check asks how much the rpm
    /// line moves WITHIN one analysis frame, and "one analysis frame" has to be the same length
    /// there as it is here or the check is about a window nothing was measured in.
    #[func]
    fn frame_layout(sample_count: i64, sample_rate_hz: f64) -> VarDictionary {
        let count = if sample_count < 0 { 0 } else { sample_count as usize };
        let (frame_len, hop, frames) = crate::spectrum::frame_layout(count, sample_rate_hz);
        let mut out = VarDictionary::new();
        out.set("frame_len", frame_len as i64);
        out.set("hop", hop as i64);
        out.set("frames", frames as i64);
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

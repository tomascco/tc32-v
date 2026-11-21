# Development environment

Details about the host and the tools that the [README](../README.md) leaves out.

## Host prerequisites

- `g++` 10 or newer (or `clang++` 5 or newer). Verilator uses C++20 coroutines for `--timing`.
- `make`.
- `perl`, because the `verilator` executable is a Perl script.
- Optional: `ccache`. If it is on the PATH, the Makefile uses it automatically (see [ccache](#ccache)).

No root access is needed. If the system compiler is too old,
`make tools` lists the alternatives: a `gcc-toolset` already installed by the
administrator, or `gxx` from conda-forge through micromamba. To pick another compiler:

```sh
CXX=/opt/rh/gcc-toolset-12/root/usr/bin/g++ make tools
CXX=/opt/rh/gcc-toolset-12/root/usr/bin/g++ make test
```

## How `make tools` works

`make tools` downloads the [OSS CAD Suite](https://github.com/YosysHQ/oss-cad-suite-build)
release pinned in `tools.lock`, checks its SHA-256 and extracts it into `.tools/` (inside
the repository, ignored by git). After that, `make test` works from any shell, fish
included, without activating any environment: the Makefile adds
`.tools/oss-cad-suite-<date>/bin` to the `PATH` by itself. The suite also ships GTKWave
and Surfer, so no separate install is needed to view waveforms.

`make tools` also installs [ossschem](https://github.com/markusdd/ossschem) (version and
SHA-256 in `tools.lock`) into `.tools/ossschem-<version>/`, for `make schematic` and
`make debug`. Its tarball ships its own Node, so the host needs nothing else. Offline:
`OSSSCHEM_TGZ=/path/ossschem-<version>-linux-x64.tar.gz make tools`.

- Running `make tools` again downloads nothing.
- The installation is atomic. If it is interrupted (Ctrl+C), nothing is left half-done;
  just run it again.
- **No access to GitHub** (for example, behind the lab proxy): download the `.tgz` on
  another machine and run `TGZ=/path/oss-cad-suite-linux-x64-YYYYMMDD.tgz make tools`.
  The SHA-256 is checked the same way.
- To keep the tools outside the repository (for example, to share one installation
  between several clones), pass `TOOLS_ROOT=/some/other/place` to every command.
- To remove everything, delete `.tools/`. A `git clean -fdx` also deletes it, and the next
  `make tools` downloads about 700 MB again.

Currently pinned: **2026-10-20**, with Verilator 5.053 (devel, after 5.052),
Yosys 0.70+176 and z3 4.15.5. The **sv-elab** frontend (`read_slang`) is **built into**
Yosys, so the Makefile does not need `-m slang`. The Makefile detects both cases
(built-in or plugin) and fails with a clear message if `read_slang` is missing.
It never falls back to `read_verilog -sv`. To pin another version, see
[Updating the stack](#updating-the-stack).

## Updating the stack

1. Pick a date at <https://github.com/YosysHQ/oss-cad-suite-build/releases>.
2. Download its linux-x64 `.tgz` and run `sha256sum` on it.
3. Change `OSS_CAD_SUITE_DATE` and `OSS_CAD_SUITE_SHA256` in `tools.lock`.
4. Run `make tools`.

The old version stays in `.tools/`, because another branch may be pinned to it. To
delete it, run `make tools-prune`.

ossschem reads the `verilator --json-only` output, whose format changes between Verilator
versions. When updating either one, run `make schematic` again. To update ossschem, change
`OSSSCHEM_VERSION` and `OSSSCHEM_SHA256` the same way.

## Seed, plusargs and verbosity

- Without `SEED`, every `make` draws a seed (1 to 2^31-1) and prints it before each test.
  When a test fails, the last line has the command that reproduces it, for example
  `SEED=1251202022 make test tc32v_counter`.
- `PLUSARGS="+name=value ..."` goes to every simulation binary; the testbench reads it with
  `$value$plusargs`. Plusargs it does not read are ignored.
- The verilator, yosys and nextpnr commands are hidden; `V=1` shows them.

## Coverage

`make coverage <module>` builds the testbench with `--coverage-user` (only covergroups and
`cover property`, without line and toggle coverage) in `build/<module>-coverage/`, runs it
and prints the `verilator_coverage` report, also saved in `report.txt` there. The binary
only writes the counters when it reaches `$finish`, so a failing test gives no report.

## Schematic

`make schematic <module>` runs ossschem on the RTL as written (not the Yosys netlist) and
writes an interactive HTML page in `build/<module>-schematic/index.html`, which opens
without a server. It opens in the default browser (`xdg-open`, or `$BROWSER`) only when
the module is named on the command line; `make schematic` alone builds every module
without opening anything. `VIEWER=` also turns the browser off. Like lint and synth, it
uses `-DSYNTHESIS` and leaves `sva/` out.

## make debug

`make debug <module>` does everything about one module in a single call, so a long
simulation does not have to run again just because the waves or the coverage were
missing:

1. `lint`, `synth` and `schematic` of the RTL with the same name, if there is one;
2. one testbench build with FST trace and coverage, run once, in `build/<module>-debug/`.

Unlike `make waves`, a failing test does not stop the rest: the waves up to the failure
stay in the FST, the viewer opens, and only then does `make` exit with the error and the
reproduce command. The coverage of a failed run is not written.

## FPGA timing report

Yosys only does logic synthesis: it does not know where the cells go or how the wires
run, so real timing only exists after place & route, in nextpnr. `make fpga <design>`
turns the nextpnr log into `build/fpga/<board>/<design>-timing.rpt`, in the spirit of
Vivado's `report_timing_summary` (formatter: `scripts/fpga-timing-report.awk`):

- **Clock summary:** target, Fmax, period and WNS (worst slack = period minus the delay
  of the worst path) of each clock. Negative WNS means FAIL, and `make fpga` stops before
  the bitstream. The report is written anyway.
- **Critical path** of each clock, step by step: `clk-to-q`, `logic`, `routing` (with the
  tiles it crosses), `setup`, with the delay of each step and the running total. Steps of
  0.00 ns inside carry chains are left out. Below each path, the RTL lines it goes
  through (`rtl/tc32v_counter.sv:28.18-28.34`).
- Paths to and from I/O pins, which have no constraint (delay only).
- **Utilization** and the **slack histogram**.

Only values after routing count; the estimates nextpnr prints after placement are
dropped. The console shows a summary (Fmax, slack and the critical path of each clock);
everything else is in the report and in `<design>-pnr.log`. The target frequency comes
from `FREQUENCY PORT` in the board's `.lpf`.

## ccache

If `ccache` is installed, the Makefile uses it to compile the C++ generated by Verilator.
The cache lives in `.tools/ccache` and is limited to 1 GB. Without `ccache`, nothing changes.

## Tab completion

`scripts/completion/` has completion for bash and fish: `make <TAB>` lists the targets,
`make test <TAB>` (and `waves`, `coverage`, `debug`) the testbenches, `make lint <TAB>`
(and `synth`, `schematic`) the RTL modules and `make fpga <TAB>` (and `prog`) the designs.
Inside a TC32-V checkout the names come straight from `rtl/`, `tb/` and `fpga/`, subfolders
included; anywhere else `make` keeps its usual completion. Nothing is installed: add one
line to your shell configuration.

- **bash**, in `~/.bashrc` (after bash-completion is loaded):

  ```sh
  source /path/to/tc32-v/scripts/completion/tc32v.bash
  ```

- **fish**, in `~/.config/fish/config.fish`:

  ```fish
  set -p fish_complete_path /path/to/tc32-v/scripts/completion
  ```

Other repositories that wrap `make` completion the same way can be enabled at the same
time: each one answers only inside its own checkout (it checks the first line of the
`Makefile`) and passes everything else to the completion loaded before it.

- **bash**: works in any order of `source` lines.
- **fish**: fish loads only the first `make.fish` in `fish_complete_path`. This one loads
  the next `make.fish` in the path before adding its own, so any order works as long as
  every `make.fish` in the path chains the same way. One that
  does not chain hides every other one that comes after it.

## Testbenches

`tb/tc32v_counter_tb.sv` is the template for the others. It has directed tests, a random
test with a `rand` class and a reference model, and a covergroup. The Verilator
limitations found so far are listed [below](#verilator-limitations).

Helper code for a testbench, such as a reference model written as a class, goes in a
`.svh` next to it and comes in with `` `include ``:

```systemverilog
`include "tc32v_ref_model.svh"   // tb/core/tc32v_ref_model.svh

module tc32v_core_tb;
```

Only the `_tb.sv` is compiled, and its folder goes into Verilator's `-I` (Verilator does
not look for includes in the folder of the including file). This way the classes of one
testbench do not show up in the others.

## Assertions (`sva/`)

Assertions live in a separate module, `sva/<module>_sva.sv`, attached to the RTL with
`bind` (template: `sva/tc32v_counter_sva.sv`). The RTL does not change, and the assertions
hold in every testbench that instantiates the module. The Makefile compiles `sva/` in the
Verilator lint and in every simulation target, never in Yosys (`synth`, `schematic`,
`fpga`).

## Verilator limitations

Found so far with Verilator 5.053:

- **Per-coverpoint `get_coverage()` is not supported** ("Unsupported: Member call on
  object"). Only `get_coverage()` on the whole covergroup works. The per-coverpoint report
  is disabled behind `` `define TC32V_COVERPOINT_REPORT `` in the testbench.
- Even without `-Wall`, some Verilator warnings are errors. For example, using the return
  value of `randomize()` (an `int`) directly as a condition gives `WIDTHTRUNC`: write
  `assert (obj.randomize() == 1)`.

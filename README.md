# TC32-V

> [!NOTE]
> **About AI use in this repository.** All of the repository infrastructure (Makefile,
> tool setup scripts, CI and verification environment) was built with AI. The example
> counter (`rtl/tc32v_counter.sv` and `tb/tc32v_counter_tb.sv`) was also written by AI,
> as a template. Everything else, meaning all of the RTL, testbenches and the rest of the
> design work, is and will be written by a human.

An RV32 RISC-V core written from scratch in SystemVerilog. It is a personal project for
learning and for my portfolio, during my graduate studies in Digital Microelectronics at UFSM.

## Roadmap

- **Stage 0 (current):** small modules (ALU, register file, counter, UART TX) and the
  verification environment.
- **Milestone 1:** single-cycle RV32I (chapter 7 of Harris & Harris) running `riscv-tests`
  and a C program.
- **Milestone 2:** 5-stage pipeline; co-simulation against Spike.
- **Milestone 3:** M and A extensions, Zicsr, Wishbone, riscv-arch-test and riscv-formal.
- **Milestone 4:** S/U modes, Sv32 MMU and Linux.
- **Later:** a separate chip repository, generated from the wafer.space GF180MCU template
  (LibreLane), instantiates this core as a submodule.

## Installation

The host needs only `g++`, `make` and `perl`, and no root access. Details, including how to
pick another compiler, are in [docs/environment.md](docs/environment.md).

```sh
make setup
```

That is the only step. It runs `make tools`, then `make lint` and `make test` once to prove
the whole flow works on this machine, and prints the next steps.
How `make tools` installs the tools, and which versions are pinned, is described in
[docs/environment.md](docs/environment.md#how-make-tools-works).

## Commands

| Command | What it does |
|---|---|
| `make setup` | full setup to start coding: `make tools`, `make lint` and `make test` |
| `make tools` | installs the tools from `tools.lock` into `.tools/` |
| `make tools-prune` | deletes OSS CAD Suite and ossschem versions other than the ones in `tools.lock` (asks for confirmation; accepts `KEEP="date1 date2"` and `YES=1`) |
| `make lint` | lints all RTL: Verilator `-Wall` and elaboration with sv-elab |
| `make lint <module>` | lints one module, for example `make lint tc32v_alu` |
| `make test` | runs every testbench plus `selfcheck`; stops at the first failure |
| `make test <module>` | runs one testbench, for example `make test tc32v_counter` |
| `make selfcheck` | confirms that a failing `assert` gives a non-zero exit code |
| `make synth` | check synthesis with Yosys (`synth_ecp5`); report in `build/synth/` |
| `make synth <module>` | checks synthesis of one module |
| `make waves <module>` | runs the testbench, writes `build/<module>.fst` and opens it in Surfer |
| `VIEWER=gtkwave make waves <module>` | opens GTKWave instead; `VIEWER=` only writes the file |
| `make coverage [module]` | runs with functional coverage and prints the covergroup report (`build/<module>-coverage/report.txt`) |
| `make schematic [module]` | interactive RTL schematic (ossschem) in `build/<module>-schematic/`, opened in the browser when the module is named |
| `make debug [module]` | lint, synth, schematic and one simulation with waves and coverage; the waves are kept even if the test fails |
| `make fpga` | builds the bitstream of every design in `fpga/icesugar-pro/` and prints a summary (max clock, slack, critical path, utilization); full timing report in `build/fpga/icesugar-pro/<design>-timing.rpt` |
| `make fpga <design>` | builds one design, for example `make fpga blink` (top `fpga/icesugar-pro/blink_top.sv`) |
| `make prog <design>` | builds the design and programs the board by copying the `.bit` to the iCELink USB drive (no root needed) |
| `make clean` | deletes `build/` |
| `SEED=N make test` | fixes the seed of the random tests (without it, every `make` draws one and prints it) |
| `PLUSARGS="+name=value" make test <module>` | passes plusargs to the testbench |
| `V=1 make <target>` | shows the full verilator, yosys and nextpnr commands |

The targets find the modules in `rtl/`, the testbenches in `tb/` and the assertions in
`sva/` by themselves, subfolders included (`rtl/core/tc32v_alu.sv` is still
`make test tc32v_alu`, so a file name cannot repeat across folders). Files
that do not declare a `module` or `package` yet, such as the `// TODO` placeholders, are
ignored. Once one of them gets a signature, it enters lint, synthesis and tests without
any change to the Makefile.

Every target that takes names, except `prog`, accepts several at once
(`make test tc32v_alu tc32v_counter`). The older form `make test-tc32v_alu` still works.
Tab completion for bash and fish is described in
[docs/environment.md](docs/environment.md#tab-completion), and the testbench template in
[docs/environment.md](docs/environment.md#testbenches).

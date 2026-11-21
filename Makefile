# TC32-V Makefile. `make help` lists the targets.
#
# All paths are relative to the repository root: run make from here.

# ---------------------------------------------------------------------------
# Tools
# ---------------------------------------------------------------------------

# tools.lock has KEY=value lines, which make reads as variables.
include tools.lock

# The OSS CAD Suite lives inside the repository, in .tools/ (ignored by git).
TOOLS_ROOT ?= $(CURDIR)/.tools
TOOLS_DIR ?= $(TOOLS_ROOT)/oss-cad-suite-$(OSS_CAD_SUITE_DATE)

# ossschem (RTL schematic) lives in .tools/ too, installed by `make tools` with
# the version from tools.lock.
OSSSCHEM_DIR ?= $(TOOLS_ROOT)/ossschem-$(OSSSCHEM_VERSION)

# Only the bin/ of the OSS CAD Suite and of ossschem go on the PATH (the OSS
# CAD Suite `environment` script is not used). This way everything works
# without activating anything, in any shell.
export PATH := $(TOOLS_DIR)/bin:$(OSSSCHEM_DIR)/bin:$(PATH)
export TOOLS_ROOT

# The `verilator` executable is a Perl script that needs the FindBin module.
# RHEL/Rocky 9 ship it in a separate package (perl-FindBin), often missing on
# machines without root. In that case we use the stand-in in scripts/perl5/.
ifeq ($(shell perl -MFindBin -e1 2>/dev/null && echo ok),)
  export PERL5LIB := $(CURDIR)/scripts/perl5$(if $(PERL5LIB),:$(PERL5LIB))
endif

# C++ compiler used by Verilator. To change it:
#   CXX=/opt/rh/gcc-toolset-12/root/usr/bin/g++ make test
CXX ?= g++

# Seed for the random tests. Without SEED, every `make` draws a new seed, so
# the tests explore different cases on each run instead of repeating the same
# sequence. The seed is printed before each test; to reproduce a failure:
# SEED=<seed> make test <module>.
# Verilator accepts 1 to 2^31-1 (0 would mean "pick one yourself", but then it
# does not print which one), so the draw stays in that range.
# := draws only once, so every test in the same make uses the same seed.
ifeq ($(SEED),)
  SEED := $(shell od -An -N4 -tu4 /dev/urandom | awk '{ print $$1 % 2147483647 + 1 }')
  SEED_INFO := $(SEED) (drawn; SEED=N to fix it)
else
  SEED_INFO := $(SEED)
endif

# The tool commands (verilator, yosys, nextpnr) are long and hide the output
# that matters, so they are not shown. To see them: V=1 make test tc32v_alu
ifeq ($(V),1)
  Q :=
else
  Q := @
endif

# Waveform viewer that `make waves` and `make debug` open when the simulation
# ends. Surfer ships with the OSS CAD Suite. VIEWER=gtkwave also works.
# VIEWER= (empty) opens nothing: it only writes the .fst and the schematic.
# The schematic (make schematic, make debug) opens in the default browser
# (xdg-open), or in the one from the BROWSER environment variable, if set.
VIEWER ?= surfer

# read_slang (sv-elab) is built into Yosys 0.67 or newer; before that it is a
# plugin loaded with `yosys -m slang`. We detect which case applies here.
# We never fall back to `read_verilog -sv`: without sv-elab, lint and synth fail.
YOSYS := $(TOOLS_DIR)/bin/yosys
SLANG_HELP_OK = $(shell $(YOSYS) $(1) -p 'help read_slang' 2>/dev/null | grep '^ *read_slang \[')
ifneq ($(wildcard $(YOSYS)),)
  ifneq ($(call SLANG_HELP_OK),)
    SLANG_MODE := builtin
    SLANG_LOAD :=
  else ifneq ($(call SLANG_HELP_OK,-m slang),)
    SLANG_MODE := plugin
    SLANG_LOAD := -m slang
  else
    SLANG_MODE := missing
  endif
endif

# ---------------------------------------------------------------------------
# File discovery
# ---------------------------------------------------------------------------

# Lists only the files that already declare a `module` or `package`. The
# `// TODO` placeholders are left out of every target; once the author writes
# the module signature, it joins lint, synth and tests by itself.
declares = $(shell grep -lE '^[[:space:]]*(module|package)[[:space:]]' $(1) /dev/null)

# The .sv files of folder $(1) whose name matches $(2), going down into the
# subfolders: rtl/, tb/ and sva/ can be organized in folders
# (rtl/core/tc32v_alu.sv). $(3) is extra conditions for find. sort makes the
# order the same on every machine (find does not guarantee an order).
find_sv = $(call declares,$(sort $(shell find $(1) -name '$(2)' $(3) 2>/dev/null)))

# The folder is not part of the name the commands use (`make test tc32v_alu`),
# so the same file name in two folders would be two modules with the same
# name. The Makefile stops here, with a clearer message than Verilator's.
dup_names = $(shell printf '%s\n' $(notdir $(1)) | sort | uniq -d)
check_unique = $(foreach n,$(call dup_names,$(1)),\
    $(error $(n) exists in more than one folder: $(filter %/$(n),$(1))))

# The file for $(2) (full name, e.g. tc32v_alu_tb.sv) in list $(1). The slash
# before the name keeps alu_tb.sv from matching tb/tc32v_alu_tb.sv.
src_of = $(filter %/$(2),$(1))

# Packages first: the modules depend on them. rtl/pkg/ is left out of the
# module search so it does not come in twice.
PKG_SRCS := $(call find_sv,rtl/pkg,*.sv)
MOD_SRCS := $(call find_sv,rtl,*.sv,-not -path 'rtl/pkg/*')
RTL_SRCS := $(PKG_SRCS) $(MOD_SRCS)
$(call check_unique,$(PKG_SRCS) $(MOD_SRCS))

# The top of each file has the same name as the file.
RTL_MODS := $(basename $(notdir $(MOD_SRCS)))

# Assertions in separate modules, attached to the RTL with `bind` (the RTL
# does not change). They go wherever Verilator runs (lint and tests), after
# the RTL they attach to. They stay out of Yosys (synth, schematic and fpga):
# assertions do not become hardware.
SVA_SRCS := $(call find_sv,sva,*.sv)
$(call check_unique,$(SVA_SRCS))

# Testbenches: tb/<module>_tb.sv, top <module>_tb. selfcheck_fail_tb is
# handled separately (it has to fail).
TB_SRCS := $(call find_sv,tb,*_tb.sv)
TESTS := $(filter-out selfcheck_fail,$(patsubst %_tb,%,$(basename $(notdir $(TB_SRCS)))))
$(call check_unique,$(TB_SRCS))

# FPGA designs: fpga/<board>/<design>_top.sv, top <design>_top. fpga/common/
# has the FPGA-only modules shared by every board (power-on reset).
BOARD ?= icesugar-pro
FPGA_COMMON_SRCS := $(call declares,$(wildcard fpga/common/*.sv))
FPGA_TOPS := $(call declares,$(wildcard fpga/$(BOARD)/*_top.sv))
DESIGNS := $(patsubst %_top,%,$(basename $(notdir $(FPGA_TOPS))))

# ---------------------------------------------------------------------------
# Modules on the command line: `make test tc32v_alu`
# ---------------------------------------------------------------------------

# make reads every word on the command line as a goal. When one of the VERBS
# is given, the other words that are not targets of this Makefile are module
# names: they go into MODULES and become targets that do nothing (at the end
# of this file). Without modules, each verb works on every module. For fpga
# and prog, the names are FPGA designs (blink) instead of modules.
#   make test                    every testbench plus selfcheck
#   make test tc32v_alu          only tc32v_alu_tb
#   make lint tc32v_alu tc32v_counter
#   make fpga blink              bitstream of fpga/$(BOARD)/blink_top.sv
#   make coverage tc32v_counter  functional coverage report
#   make schematic tc32v_alu     RTL schematic in the browser
#   make debug tc32v_counter     everything at once (see the debug target)
VERBS := test waves coverage debug lint synth schematic fpga prog
TARGETS := help setup tools tools-prune selfcheck clean $(VERBS) \
    $(addsuffix -%,$(VERBS) check)

GIVEN_VERBS := $(filter $(VERBS),$(MAKECMDGOALS))
ifneq ($(GIVEN_VERBS),)
  MODULES := $(filter-out $(TARGETS),$(MAKECMDGOALS))
endif

# `make test waves tc32v_alu` is ambiguous: which verb gets the module?
ifneq ($(MODULES),)
  ifneq ($(words $(GIVEN_VERBS)),1)
    $(error Modules can follow only one of: $(VERBS). Got: $(GIVEN_VERBS))
  endif
endif

ifneq ($(filter waves,$(MAKECMDGOALS)),)
  ifeq ($(MODULES),)
    $(error Usage: make waves <module>. Testbenches found: $(or $(TESTS),(none)))
  endif
endif

# The board holds one bitstream at a time, so prog takes exactly one design.
ifneq ($(filter prog,$(MAKECMDGOALS)),)
  ifneq ($(words $(MODULES)),1)
    $(error Usage: make prog <design>. Designs found for $(BOARD): $(or $(DESIGNS),(none)))
  endif
endif

# ---------------------------------------------------------------------------
# Flags
# ---------------------------------------------------------------------------

# --binary already implies --timing. -j 0 uses every core to compile.
VERILATOR_TB_FLAGS := --binary --assert --x-assign unique --x-initial unique \
    -Irtl -Irtl/pkg -j 0 --quiet

# FST trace for waves and debug. By default Verilator leaves out of the dump
# any unpacked array with more than 32 elements (memories, register file).
# --trace-max-array raises that limit.
VERILATOR_TRACE_FLAGS = --trace-fst --trace-max-array 1024 $(VERILATOR_FST_FLAGS)

# Passed to the make that Verilator calls to compile the C++. LINK must be the
# same compiler too (otherwise linking uses the system g++). PYTHON3 is the
# one from the OSS CAD Suite, used by an internal Verilator script.
VERILATOR_MAKEFLAGS := -MAKEFLAGS "CXX=$(CXX)" -MAKEFLAGS "LINK=$(CXX)" \
    -MAKEFLAGS "PYTHON3=$(TOOLS_DIR)/bin/tabbypy3"

# Verilator always links with -latomic. On RHEL/Rocky 9 the libatomic package
# is often missing (installing it needs root) and the link fails. On x86-64 the
# atomics Verilator uses do not need that library, so we drop it in that case.
ifeq ($(shell echo 'int main(){}' | $(CXX) -x c++ - -o /dev/null -latomic 2>/dev/null && echo ok),)
  VERILATOR_MAKEFLAGS += -MAKEFLAGS "CFG_LDLIBS_THREADS=-pthread"
endif

# --trace-fst (make waves, make debug) includes <lz4.h> and links -llz4. RHEL/Rocky 9
# ship lz4.h in a separate package (lz4-devel), often missing on machines
# without root. In that case `make tools` builds a local copy in .tools/ and
# we point the compiler at it.
LZ4_DIR := $(TOOLS_ROOT)/lz4-$(LZ4_VERSION)
ifeq ($(shell echo 'int main() { return LZ4_compressBound(1) > 0 ? 0 : 1; }' | $(CXX) -x c++ -include lz4.h - -o /dev/null -llz4 2>/dev/null && echo ok),)
  VERILATOR_FST_FLAGS := -CFLAGS -I$(LZ4_DIR)/include -LDFLAGS -L$(LZ4_DIR)/lib
endif

# ccache (optional): if it is installed on the host, it speeds up recompiling
# the C++ generated by Verilator. The cache lives in .tools/ccache, capped at
# 1 GB; ccache deletes the oldest entries when it reaches the limit.
ifneq ($(shell command -v ccache 2>/dev/null),)
  VERILATOR_MAKEFLAGS += -MAKEFLAGS "OBJCACHE=ccache"
  export CCACHE_DIR := $(TOOLS_ROOT)/ccache
  export CCACHE_MAXSIZE := 1G
endif

# FPGA board. The iCESugar-Pro has an LFE5U-25F, CABGA256 package, speed
# grade 6. Another board needs its own fpga/<board>/ (tops and <board>.lpf)
# and its own NEXTPNR_FLAGS.
NEXTPNR_FLAGS := --25k --package CABGA256 --speed 6
BOARD_LPF := fpga/$(BOARD)/$(BOARD).lpf
FPGA_BUILD := build/fpga/$(BOARD)

# The board's programmer (iCELink) shows up as a USB drive. The desktop mounts
# it under /run/media/$USER (RHEL, Fedora) or /media/$USER (Ubuntu); to use
# another place: make prog blink ICELINK=/mount/point
ICELINK ?= $(firstword $(wildcard /run/media/$(USER)/iCELink /media/$(USER)/iCELink))

# --x-initial unique only randomizes initial values if we ask for it at run
# time. This helps find registers that depend on a power-up value.
SIM_ARGS = +verilator+seed+$(SEED) +verilator+rand+reset+2 $(PLUSARGS)

# Extra plusargs passed to every simulation binary, to tune the testbench
# without recompiling. The testbench reads them with $$value$$plusargs, e.g.:
#   PLUSARGS="+cycles=5000" make test tc32v_counter
# Plusargs the testbench does not read are ignored.
PLUSARGS ?=

# Failure message for the testbench of $(2), with the `make $(1) $(2)`
# command that reproduces the same run (same seed and plusargs).
fail_msg = $(2): FAILED with seed $(SEED). To reproduce: SEED=$(SEED)$(if $(PLUSARGS), PLUSARGS='$(PLUSARGS)') make $(1) $(2)

# Runs binary $(1) of the testbench of $(2) with the make seed. The seed is
# printed before the simulation and, if the test fails, again at the end
# together with the command that reproduces the failure. $(3) is extra
# simulation arguments.
define run_tb
	@echo "$(2): seed $(SEED)"
	@$(1) $(SIM_ARGS) $(3) || { \
	    status=$$?; \
	    echo "$(call fail_msg,test,$(2))"; \
	    exit $$status; \
	}
endef

# Opens the waveform $(1) in $(VIEWER), in the background, so make returns
# right away. The viewer output goes to $(2). Without a display (ssh, CI) it
# only prints a note.
define open_viewer
	@if [ -z "$(VIEWER)" ]; then :; \
	elif [ -z "$$DISPLAY$$WAYLAND_DISPLAY" ]; then \
	    echo "no display: $(VIEWER) not opened"; \
	else \
	    echo "opening $(1) in $(VIEWER) (log in $(2))"; \
	    nohup $(VIEWER) $(1) >$(2) 2>&1 & \
	fi
endef

# Opens the schematic in folder $(1) in the browser. `ossschem open` calls
# xdg-open (or $$BROWSER) in the background and returns right away. VIEWER=
# (empty) turns this one off too, so there is a single way to open nothing.
define open_schematic
	@if [ -z "$(VIEWER)" ]; then :; \
	elif [ -z "$$DISPLAY$$WAYLAND_DISPLAY" ]; then \
	    echo "no display: schematic not opened"; \
	else \
	    echo "opening $(1)/index.html in the browser"; \
	    ossschem open $(1) >/dev/null; \
	fi
endef

# Compiles the testbench of $(1) with all the RTL and SVA into build/$(2)/.
# $(3) is extra flags. The testbench folder goes into -I so it can `include
# helper files (.svh) next to it, such as a reference model written as a
# class: Verilator does not look for includes in the folder of the including
# file, only in the -I folders. Including instead of compiling all of tb/
# keeps the classes of one testbench out of the others.
define build_tb
	@mkdir -p build/$(2)
	@echo "$(1): building the testbench"
	$(Q)verilator $(VERILATOR_TB_FLAGS) $(VERILATOR_MAKEFLAGS) $(3) \
	    -I$(dir $(call src_of,$(TB_SRCS),$(1)_tb.sv)) \
	    --top-module $(1)_tb --Mdir build/$(2) -o $(1)_tb \
	    $(RTL_SRCS) $(SVA_SRCS) $(call src_of,$(TB_SRCS),$(1)_tb.sv)
endef

# Fails with a clear message if the testbench for $* is still a placeholder.
define require_tb
	@if [ -z "$(call src_of,$(TB_SRCS),$*_tb.sv)" ]; then \
	    echo "ERROR: tb/$*_tb.sv (or tb/<folder>/$*_tb.sv) does not exist or does not declare a module yet."; \
	    exit 1; \
	fi
endef

# The same for the RTL of $*, used by lint, synth and schematic.
define require_rtl
	@if [ -z "$(filter $*,$(RTL_MODS))" ]; then \
	    echo "ERROR: rtl/$*.sv (or rtl/<folder>/$*.sv) does not exist or does not declare a module yet."; \
	    exit 1; \
	fi
endef

# The same for the board top of design $*, used by fpga and prog.
define require_top
	@if [ -z "$(filter $*,$(DESIGNS))" ]; then \
	    echo "ERROR: fpga/$(BOARD)/$*_top.sv does not exist or does not declare a module yet."; \
	    exit 1; \
	fi
endef

# ---------------------------------------------------------------------------
# Targets
# ---------------------------------------------------------------------------

.PHONY: help setup tools tools-prune check-tools check-slang check-ossschem lint test selfcheck synth waves coverage schematic debug fpga prog clean

help:
	@echo "Targets:"
	@echo "  make setup            full setup: tools, lint and test"
	@echo "  make tools            installs the tools from tools.lock into .tools/"
	@echo "  make tools-prune      deletes OSS CAD Suite and ossschem versions not in tools.lock"
	@echo "  make lint [module]    lints the RTL (Verilator -Wall and sv-elab)"
	@echo "  make test             runs every testbench (includes selfcheck)"
	@echo "  make test <module>    runs one testbench, e.g. make test tc32v_counter"
	@echo "  make selfcheck        confirms that a failing assert fails the test"
	@echo "  make synth [module]   check synthesis (Yosys, synth_ecp5)"
	@echo "  make waves <module>   runs one testbench, writes build/<module>.fst, opens Surfer"
	@echo "  make coverage [module] runs with coverage and prints the covergroup report"
	@echo "  make schematic [module] RTL schematic (ossschem), opened in the browser"
	@echo "  make debug [module]   everything: lint, synth, schematic and one simulation with"
	@echo "                        waves and coverage (the waves are kept even if the test fails)"
	@echo "  make fpga [design]    bitstream of fpga/$(BOARD)/<design>_top.sv, with a summary"
	@echo "  make prog <design>    builds the design and programs the board (iCELink drive)"
	@echo "  make clean            deletes build/"
	@echo ""
	@echo "Every target above that takes names, except prog, accepts several: make test a b"
	@echo "Tab completion for bash and fish: see scripts/completion/."
	@echo ""
	@echo "Variables: SEED=$(SEED_INFO) CXX=$(CXX) VIEWER=$(VIEWER) BOARD=$(BOARD)"
	@echo "           PLUSARGS=\"+name=value ...\" passes plusargs to the testbench"
	@echo "           V=1 shows the verilator, yosys and nextpnr commands"
	@echo "Modules found:     $(or $(RTL_MODS),(none))"
	@echo "Testbenches found: $(or $(TESTS),(none))"
	@echo "Designs found:     $(or $(DESIGNS),(none))"

tools:
	CXX="$(CXX)" bash scripts/setup-tools.sh

# Full setup to start coding: installs the tools and runs lint and tests once,
# proving the flow works on this machine. lint and test run in a fresh make
# because the sv-elab detection (at the top of this file) happens when the
# Makefile is read, before the tools exist.
setup: tools
	$(MAKE) lint test
	@echo ""
	@echo "Setup done. Next steps:"
	@echo "  - write the RTL in rtl/ and the testbench in tb/ (template: tb/tc32v_counter_tb.sv)"
	@echo "  - make test <module>   runs one testbench"
	@echo "  - make waves <module>  writes build/<module>.fst and opens it in Surfer"
	@echo "  - make debug <module>  lint, synth, schematic, waves and coverage in one go"
	@echo "  - make help            lists every target"

# Accepts KEEP="date1 date2" and YES=1 (passed through the environment).
tools-prune:
	bash scripts/prune-tools.sh

check-tools:
	@if [ ! -d "$(TOOLS_DIR)" ]; then \
	    echo "ERROR: $(TOOLS_DIR) does not exist. Run \`make tools\`."; \
	    exit 1; \
	fi

check-slang: check-tools
	@if [ "$(SLANG_MODE)" != builtin ] && [ "$(SLANG_MODE)" != plugin ]; then \
	    echo "ERROR: the Yosys in $(TOOLS_DIR) has no read_slang (sv-elab)."; \
	    exit 1; \
	fi

check-ossschem: check-tools
	@if [ ! -x "$(OSSSCHEM_DIR)/bin/ossschem" ]; then \
	    echo "ERROR: $(OSSSCHEM_DIR) does not exist. Run \`make tools\`."; \
	    exit 1; \
	fi

# --- lint -------------------------------------------------------------------

lint: $(addprefix lint-,$(or $(MODULES),$(RTL_MODS)))

lint-%: check-slang
	$(require_rtl)
	$(Q)verilator --lint-only -Wall --quiet -Irtl -Irtl/pkg --top-module $* $(RTL_SRCS) $(SVA_SRCS)
	$(Q)yosys -q $(SLANG_LOAD) -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $* $(RTL_SRCS); hierarchy -check -top $*"
	@echo "lint $*: ok"

# --- tests ------------------------------------------------------------------

# With modules on the command line, only their testbenches run (no selfcheck).
test: $(if $(MODULES),,selfcheck) $(addprefix test-,$(or $(MODULES),$(TESTS)))

test-%: check-tools
	$(require_tb)
	$(call build_tb,$*,$*)
	$(call run_tb,build/$*/$*_tb,$*)

# selfcheck_fail_tb has an assert that fails on purpose. This target only
# passes if the binary builds and then exits with a non-zero code.
selfcheck: check-tools
	$(call build_tb,selfcheck_fail,selfcheck_fail)
	@if build/selfcheck_fail/selfcheck_fail_tb $(SIM_ARGS) >build/selfcheck_fail/run.log 2>&1; then \
	    cat build/selfcheck_fail/run.log; \
	    echo "selfcheck: ERROR: selfcheck_fail_tb passed, but it should fail."; \
	    exit 1; \
	else \
	    echo "selfcheck: ok (selfcheck_fail_tb failed with code $$?, as expected)"; \
	fi

waves: $(addprefix waves-,$(MODULES))

waves-%: check-tools
	$(require_tb)
	$(call build_tb,$*,$*-waves,$(VERILATOR_TRACE_FLAGS))
	$(call run_tb,build/$*-waves/$*_tb,$*,+dumpfile=build/$*.fst)
	@echo "waves in build/$*.fst"
	$(call open_viewer,build/$*.fst,build/$*-waves/viewer.log)

# --- coverage ---------------------------------------------------------------

coverage: $(addprefix coverage-,$(or $(MODULES),$(TESTS)))

# --coverage-user turns on only the coverage written by the author
# (covergroups and `cover property`), without line and toggle coverage, which
# would clutter the report. The instrumentation slows the simulation down, so
# it gets a build separate from `make test`. The binary writes the counters to
# coverage.dat when it reaches $finish; a test that fails midway writes no
# report. The old .dat is deleted first: the binary would append to it, and the
# report would mix different runs.
coverage-%: check-tools
	$(require_tb)
	$(call build_tb,$*,$*-coverage,--coverage-user)
	@rm -f build/$*-coverage/coverage.dat
	$(call run_tb,build/$*-coverage/$*_tb,$*,+verilator+coverage+file+build/$*-coverage/coverage.dat)
	@verilator_coverage --filter-type covergroup --report hier \
	    build/$*-coverage/coverage.dat | tee build/$*-coverage/report.txt
	@echo "report in build/$*-coverage/report.txt"

# --- synthesis --------------------------------------------------------------

synth: $(addprefix synth-,$(or $(MODULES),$(RTL_MODS)))

synth-%: check-slang
	$(require_rtl)
	@mkdir -p build/synth
	$(Q)yosys -q $(SLANG_LOAD) -l build/synth/$*.log \
	    -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $* $(RTL_SRCS); synth_ecp5 -top $*; tee -o build/synth/$*.stat stat"
	@echo "synth $*: ok (sv-elab $(SLANG_MODE); report in build/synth/$*.stat)"

# --- schematic --------------------------------------------------------------

schematic: $(addprefix schematic-,$(or $(MODULES),$(RTL_MODS)))

# ossschem runs Verilator with --json-only and turns the design tree into an
# interactive HTML page in build/<module>-schematic/ (opens without a server).
# It is the schematic of the RTL as written, not the Yosys netlist. -DSYNTHESIS,
# as in lint and synth, drops the assertions inside the RTL; sva/ stays out.
# The browser opens only when the modules are on the command line: `make
# schematic` alone builds every one, and opening one tab per module would be
# too much.
schematic-%: check-ossschem
	$(require_rtl)
	@mkdir -p build/$*-schematic
	$(Q)ossschem build --top $* --out-dir build/$*-schematic \
	    --verilator $(TOOLS_DIR)/bin/verilator $(RTL_SRCS) \
	    -- -Irtl -Irtl/pkg -DSYNTHESIS >build/$*-schematic/ossschem.log 2>&1 || { \
	    cat build/$*-schematic/ossschem.log; \
	    exit 1; \
	}
	@echo "schematic $*: ok (build/$*-schematic/index.html)"
	$(if $(MODULES),$(call open_schematic,build/$*-schematic))

# --- debug ------------------------------------------------------------------

debug: $(addprefix debug-,$(or $(MODULES),$(TESTS)))

# Everything about one module in a single call, so a long simulation does not
# have to run again just because the waves or the coverage were missing:
#   1. lint, synth and schematic of the RTL with the same name (if it exists);
#   2. a single testbench build with FST trace and coverage, run once.
# Unlike waves, a failing test (in a $fatal or an assert) does not stop the
# rest: the waves up to the failure stay in the FST (on $fatal the Verilator
# runtime closes the file before exiting), the viewer opens, and only at the
# end does make exit with the error. The coverage of a failed run is not
# written: the binary only writes it at the end of main(), which $fatal does
# not reach. It would not help anyway: the checker failed the run, and the
# empty bins only say the simulation stopped early. Everything goes to
# build/<module>-debug/.
#
# The steps of item 1 are prerequisites, picked with .SECONDEXPANSION: in the
# second expansion ($$ becomes $) $* already holds the module name, and the
# filter checks whether rtl/ has a module with that name.
.SECONDEXPANSION:
debug-%: check-tools check-ossschem \
    $$(addsuffix -$$*,$$(if $$(filter $$*,$$(RTL_MODS)),lint synth schematic))
	$(require_tb)
	$(call build_tb,$*,$*-debug,$(VERILATOR_TRACE_FLAGS) --coverage-user)
	@rm -f $(addprefix build/$*-debug/,$*.fst coverage.dat report.txt status)
	@echo "$*: seed $(SEED)"
	@build/$*-debug/$*_tb $(SIM_ARGS) +dumpfile=build/$*-debug/$*.fst \
	    +verilator+coverage+file+build/$*-debug/coverage.dat; \
	    echo $$? >build/$*-debug/status
	@# The whole report goes to the file; on screen, only the testbench total
	@# and each covergroup's (names with at most one dot). A testbench without
	@# a covergroup writes a coverage.dat with only the header (no "C " lines).
	@if [ "$$(cat build/$*-debug/status)" != 0 ]; then \
	    echo "coverage: not written (the test failed)"; \
	elif grep -q '^C ' build/$*-debug/coverage.dat 2>/dev/null; then \
	    verilator_coverage --filter-type covergroup --report hier \
	        build/$*-debug/coverage.dat >build/$*-debug/report.txt; \
	    awk 'NR == 1 || split($$1, part, ".") <= 2' build/$*-debug/report.txt; \
	    echo "report in build/$*-debug/report.txt"; \
	fi
	@if [ -f build/$*-debug/$*.fst ]; then \
	    echo "waves in build/$*-debug/$*.fst"; \
	else \
	    echo "the testbench wrote no waves (it must read +dumpfile; template: tb/tc32v_counter_tb.sv)"; \
	fi
	$(if $(MODULES),$(call open_viewer,build/$*-debug/$*.fst,build/$*-debug/viewer.log))
	@status=$$(cat build/$*-debug/status); \
	if [ "$$status" != 0 ]; then \
	    echo "$(call fail_msg,debug,$*)"; \
	    exit $$status; \
	fi
	@echo "debug $*: ok"

# --- FPGA -------------------------------------------------------------------

fpga: $(addprefix fpga-,$(or $(MODULES),$(DESIGNS)))

# Synthesis (Yosys), place & route (nextpnr) and bitstream (ecppack) of
# fpga/$(BOARD)/$*_top.sv. --timing-allow-fail keeps nextpnr from stopping
# on a timing failure, so the summary can show it; the summary then fails
# and the bitstream is not generated. The timing report (<design>-timing.rpt)
# is written before the summary, so it exists even when timing fails.
fpga-%: check-slang
	$(require_top)
	@mkdir -p $(FPGA_BUILD)
	$(Q)yosys -q $(SLANG_LOAD) -l $(FPGA_BUILD)/$*-synth.log \
	    -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $*_top $(RTL_SRCS) $(FPGA_COMMON_SRCS) fpga/$(BOARD)/$*_top.sv; synth_ecp5 -top $*_top -json $(FPGA_BUILD)/$*.json"
	$(Q)nextpnr-ecp5 -q $(NEXTPNR_FLAGS) --timing-allow-fail \
	    --json $(FPGA_BUILD)/$*.json --lpf $(BOARD_LPF) \
	    --textcfg $(FPGA_BUILD)/$*.config -l $(FPGA_BUILD)/$*-pnr.log
	@awk -v title="$* on $(BOARD)" -f scripts/fpga-timing-report.awk \
	    $(FPGA_BUILD)/$*-pnr.log > $(FPGA_BUILD)/$*-timing.rpt
	@bash scripts/fpga-summary.sh $(FPGA_BUILD)/$*-pnr.log "$* on $(BOARD)" \
	    $(FPGA_BUILD)/$*-timing.rpt
	$(Q)ecppack $(FPGA_BUILD)/$*.config $(FPGA_BUILD)/$*.bit
	@echo "fpga $*: ok (bitstream in $(FPGA_BUILD)/$*.bit)"

prog: $(addprefix prog-,$(MODULES))

# Copying the .bit to the iCELink drive programs the board's flash. icesprog
# does the same over USB, but /dev/hidraw* is root-only without a udev rule,
# and the lab PC has no root.
prog-%: fpga-%
	@if [ -z "$(ICELINK)" ] || [ ! -d "$(ICELINK)" ]; then \
	    echo "ERROR: iCELink drive not found in /run/media/$(USER) or /media/$(USER)."; \
	    echo "Plug in the board, or give the mount point: make prog $* ICELINK=/path"; \
	    exit 1; \
	fi
	cp $(FPGA_BUILD)/$*.bit "$(ICELINK)/"
	sync
	@echo "prog $*: copied to $(ICELINK); the board is programming itself"

clean:
	rm -rf build

# The module names given on the command line (see MODULES) are goals too. This
# rule makes them do nothing; the work is done by the verb that came with them.
ifneq ($(MODULES),)
.PHONY: $(MODULES)
$(MODULES):
	@:
endif

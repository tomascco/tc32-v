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

# Only the OSS CAD Suite bin/ goes on the PATH (its `environment` script is not
# used). This way everything works without activating anything, in any shell.
export PATH := $(TOOLS_DIR)/bin:$(PATH)
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

# Seed for the random tests. To change it: SEED=2 make test
SEED ?= 1

# Waveform viewer that `make waves` opens when the simulation ends. Surfer
# ships with the OSS CAD Suite. VIEWER=gtkwave also works; VIEWER= (empty)
# only writes the .fst.
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

# Packages first: the modules depend on them.
PKG_SRCS := $(call declares,$(wildcard rtl/pkg/*.sv))
MOD_SRCS := $(call declares,$(wildcard rtl/*.sv))
RTL_SRCS := $(PKG_SRCS) $(MOD_SRCS)

# The top of each file has the same name as the file.
RTL_MODS := $(basename $(notdir $(MOD_SRCS)))

# Testbenches: tb/<module>_tb.sv, top <module>_tb. selfcheck_fail_tb is
# handled separately (it has to fail).
TB_SRCS := $(call declares,$(wildcard tb/*_tb.sv))
TESTS := $(filter-out selfcheck_fail,$(patsubst %_tb,%,$(basename $(notdir $(TB_SRCS)))))

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
VERBS := test waves lint synth fpga prog
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

# --trace-fst (make waves-*) includes <lz4.h> and links -llz4. RHEL/Rocky 9
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
SIM_ARGS = +verilator+seed+$(SEED) +verilator+rand+reset+2

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

# Compiles tb/$(1)_tb.sv with all the RTL into build/$(2)/. $(3) is extra flags.
define build_tb
	@mkdir -p build/$(2)
	verilator $(VERILATOR_TB_FLAGS) $(VERILATOR_MAKEFLAGS) $(3) \
	    --top-module $(1)_tb --Mdir build/$(2) -o $(1)_tb \
	    $(RTL_SRCS) tb/$(1)_tb.sv
endef

# Fails with a clear message if the testbench for $* is still a placeholder.
define require_tb
	@if [ -z "$(filter tb/$*_tb.sv,$(TB_SRCS))" ]; then \
	    echo "ERROR: tb/$*_tb.sv does not exist or does not declare a module yet."; \
	    exit 1; \
	fi
endef

# The same for the RTL of $*, used by lint and synth.
define require_rtl
	@if [ -z "$(filter $*,$(RTL_MODS))" ]; then \
	    echo "ERROR: rtl/$*.sv does not exist or does not declare a module yet."; \
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

.PHONY: help setup tools tools-prune check-tools check-slang lint test selfcheck synth waves fpga prog clean

help:
	@echo "Targets:"
	@echo "  make setup            full setup: tools, lint and test"
	@echo "  make tools            installs the tools from tools.lock into .tools/"
	@echo "  make tools-prune      deletes OSS CAD Suite versions not in tools.lock"
	@echo "  make lint [module]    lints the RTL (Verilator -Wall and sv-elab)"
	@echo "  make test             runs every testbench (includes selfcheck)"
	@echo "  make test <module>    runs one testbench, e.g. make test tc32v_counter"
	@echo "  make selfcheck        confirms that a failing assert fails the test"
	@echo "  make synth [module]   check synthesis (Yosys, synth_ecp5)"
	@echo "  make waves <module>   runs one testbench, writes build/<module>.fst, opens Surfer"
	@echo "  make fpga [design]    bitstream of fpga/$(BOARD)/<design>_top.sv, with a summary"
	@echo "  make prog <design>    builds the design and programs the board (iCELink drive)"
	@echo "  make clean            deletes build/"
	@echo ""
	@echo "lint, test, synth, waves and fpga accept several names: make test a b"
	@echo "Tab completion for bash and fish: see scripts/completion/."
	@echo ""
	@echo "Variables: SEED=$(SEED) CXX=$(CXX) VIEWER=$(VIEWER) BOARD=$(BOARD)"
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
	@echo "  - make waves <module>  writes build/<module>.fst; open it with"
	@echo "      $(TOOLS_DIR)/bin/surfer build/<module>.fst"
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

# --- lint -------------------------------------------------------------------

lint: $(addprefix lint-,$(or $(MODULES),$(RTL_MODS)))

lint-%: check-slang
	$(require_rtl)
	verilator --lint-only -Wall --quiet -Irtl -Irtl/pkg --top-module $* $(RTL_SRCS)
	yosys -q $(SLANG_LOAD) -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $* $(RTL_SRCS); hierarchy -check -top $*"
	@echo "lint $*: ok"

# --- tests ------------------------------------------------------------------

# With modules on the command line, only their testbenches run (no selfcheck).
test: $(if $(MODULES),,selfcheck) $(addprefix test-,$(or $(MODULES),$(TESTS)))

test-%: check-tools
	$(require_tb)
	$(call build_tb,$*,$*)
	build/$*/$*_tb $(SIM_ARGS)

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

# By default Verilator leaves out of the dump any unpacked array with more than
# 32 elements (memories, register file). --trace-max-array raises that limit.
waves-%: check-tools
	$(require_tb)
	$(call build_tb,$*,$*-waves,--trace-fst --trace-max-array 1024 $(VERILATOR_FST_FLAGS))
	build/$*-waves/$*_tb $(SIM_ARGS) +dumpfile=build/$*.fst
	@echo "waves in build/$*.fst"
	$(call open_viewer,build/$*.fst,build/$*-waves/viewer.log)

# --- synthesis --------------------------------------------------------------

synth: $(addprefix synth-,$(or $(MODULES),$(RTL_MODS)))

synth-%: check-slang
	$(require_rtl)
	@mkdir -p build/synth
	yosys -q $(SLANG_LOAD) -l build/synth/$*.log \
	    -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $* $(RTL_SRCS); synth_ecp5 -top $*; tee -o build/synth/$*.stat stat"
	@echo "synth $*: ok (sv-elab $(SLANG_MODE); report in build/synth/$*.stat)"

# --- FPGA -------------------------------------------------------------------

fpga: $(addprefix fpga-,$(or $(MODULES),$(DESIGNS)))

# Synthesis (Yosys), place & route (nextpnr) and bitstream (ecppack) of
# fpga/$(BOARD)/$*_top.sv. --timing-allow-fail keeps nextpnr from stopping
# on a timing failure, so the summary can show it; the summary then fails
# and the bitstream is not generated.
fpga-%: check-slang
	$(require_top)
	@mkdir -p $(FPGA_BUILD)
	yosys -q $(SLANG_LOAD) -l $(FPGA_BUILD)/$*-synth.log \
	    -p "read_slang -DSYNTHESIS -I rtl -I rtl/pkg --top $*_top $(RTL_SRCS) $(FPGA_COMMON_SRCS) fpga/$(BOARD)/$*_top.sv; synth_ecp5 -top $*_top -json $(FPGA_BUILD)/$*.json"
	nextpnr-ecp5 -q $(NEXTPNR_FLAGS) --timing-allow-fail \
	    --json $(FPGA_BUILD)/$*.json --lpf $(BOARD_LPF) \
	    --textcfg $(FPGA_BUILD)/$*.config -l $(FPGA_BUILD)/$*-pnr.log
	@bash scripts/fpga-summary.sh $(FPGA_BUILD)/$*-pnr.log "$* on $(BOARD)"
	ecppack $(FPGA_BUILD)/$*.config $(FPGA_BUILD)/$*.bit
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

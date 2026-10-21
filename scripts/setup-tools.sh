#!/usr/bin/env bash
#
# Installs the OSS CAD Suite pinned in tools.lock, without root.
#
# Usage (normally through `make tools`):
#   scripts/setup-tools.sh
#
# Optional environment variables:
#   TOOLS_ROOT  directory where the versions live (default: .tools/ inside the
#               repository, ignored by git)
#   CXX         C++ compiler used by Verilator (default: g++)
#   TGZ         path to an already downloaded .tgz (offline install)
#
# The install is atomic: everything happens in a temporary directory inside
# TOOLS_ROOT, and only at the end is it renamed to oss-cad-suite-<date>. If the
# script is interrupted, the final directory is never left half-done.
#
# Nothing persistent is written outside TOOLS_ROOT. To remove
# everything, just delete the .tools/ directory.
#
# Old versions are not deleted here. Use `make tools-prune`.

set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=../tools.lock
source "$REPO_ROOT/tools.lock"

TOOLS_ROOT="${TOOLS_ROOT:-$REPO_ROOT/.tools}"
CXX="${CXX:-g++}"
TGZ="${TGZ:-}"

DATE="$OSS_CAD_SUITE_DATE"
EXPECTED_SHA256="$OSS_CAD_SUITE_SHA256"
TGZ_NAME="oss-cad-suite-linux-x64-${DATE//-/}.tgz"
URL="https://github.com/YosysHQ/oss-cad-suite-build/releases/download/${DATE}/${TGZ_NAME}"
FINAL_DIR="$TOOLS_ROOT/oss-cad-suite-$DATE"

# Minimums. Verilator: covergroups (5.050) and UVM 2020-3.2 (5.052).
# Compiler: --timing (enabled by --binary) uses C++20 coroutines; the
# Verilator documentation asks for "GCC 10, Clang 5, or newer".
MIN_VERILATOR=5.052
MIN_GCC=10
MIN_CLANG=5

info() { echo "[setup-tools] $*"; }
die() {
    echo "[setup-tools] ERROR: $*" >&2
    exit 1
}

# Returns success if version $1 >= $2 (comparison in the style 5.052 >= 5.050).
version_ge() {
    [ "$(printf '%s\n' "$2" "$1" | sort -V | head -n 1)" = "$2" ]
}

# ---------------------------------------------------------------------------
# Host prerequisites
# ---------------------------------------------------------------------------

print_compiler_help() {
    cat >&2 <<EOF

Verilator needs a C++ compiler with coroutines:
GCC $MIN_GCC or newer, or Clang $MIN_CLANG or newer.
(Rocky Linux 8 ships GCC 8; Rocky Linux 9 ships GCC 11.)

Alternatives without root:

  1) A gcc-toolset already installed by the administrator:
EOF
    local found=0 gxx
    for gxx in /opt/rh/gcc-toolset-*/root/usr/bin/g++; do
        if [ -x "$gxx" ]; then
            echo "       found: $gxx" >&2
            found=1
        fi
    done
    if [ "$found" = 0 ]; then
        echo "       (none found in /opt/rh/gcc-toolset-*)" >&2
    fi
    cat >&2 <<EOF
     Use it like this (in every make command):
       CXX=/opt/rh/gcc-toolset-N/root/usr/bin/g++ make tools
       CXX=/opt/rh/gcc-toolset-N/root/usr/bin/g++ make test

  2) micromamba with gxx and make from conda-forge, inside the repository .tools/:
       cd $REPO_ROOT
       mkdir -p .tools/micromamba
       curl -Ls https://micro.mamba.pm/api/micromamba/linux-64/latest | tar -xj -C .tools/micromamba bin/micromamba
       .tools/micromamba/bin/micromamba create -y -r .tools/micromamba -p .tools/cxx -c conda-forge gxx make
     Then:
       CXX=$REPO_ROOT/.tools/cxx/bin/g++ .tools/cxx/bin/make tools
       CXX=$REPO_ROOT/.tools/cxx/bin/g++ .tools/cxx/bin/make test

EOF
}

check_host() {
    command -v make >/dev/null 2>&1 ||
        { print_compiler_help; die "'make' not found on the PATH."; }
    # The `verilator` executable is a Perl script.
    command -v perl >/dev/null 2>&1 ||
        die "'perl' not found on the PATH (Verilator needs it)."
    # RHEL/Rocky 9 ship FindBin in a separate package (perl-FindBin). Without
    # it, use the stand-in in scripts/perl5/ (the Makefile does the same).
    if ! perl -MFindBin -e1 2>/dev/null; then
        export PERL5LIB="$REPO_ROOT/scripts/perl5${PERL5LIB:+:$PERL5LIB}"
        info "perl:      FindBin missing; using scripts/perl5/FindBin.pm"
    fi
    command -v sha256sum >/dev/null 2>&1 ||
        die "'sha256sum' not found on the PATH."

    if ! command -v "$CXX" >/dev/null 2>&1; then
        print_compiler_help
        die "compiler '$CXX' not found (set CXX=...)."
    fi

    # Ask the compiler itself what it is. Clang also defines __GNUC__, so it
    # is tested first.
    local macros major
    macros="$(echo | "$CXX" -dM -E -x c++ - 2>/dev/null)" ||
        die "could not run '$CXX'."
    if major="$(echo "$macros" | awk '$2 == "__clang_major__" { print $3 }')" && [ -n "$major" ]; then
        if [ "$major" -lt "$MIN_CLANG" ]; then
            print_compiler_help
            die "'$CXX' is Clang $major; Clang $MIN_CLANG or newer is required."
        fi
        info "compiler:  $CXX (Clang $major)"
    elif major="$(echo "$macros" | awk '$2 == "__GNUC__" { print $3 }')" && [ -n "$major" ]; then
        if [ "$major" -lt "$MIN_GCC" ]; then
            print_compiler_help
            die "'$CXX' is GCC $major; GCC $MIN_GCC or newer is required."
        fi
        info "compiler:  $CXX (GCC $major)"
    else
        print_compiler_help
        die "did not recognize the compiler '$CXX'."
    fi
}

# ---------------------------------------------------------------------------
# Checking an installation (final, or still in the temporary directory)
# ---------------------------------------------------------------------------

check_tools() {
    local dir="$1" v

    [ -x "$dir/bin/verilator" ] || die "$dir/bin/verilator does not exist."
    [ -x "$dir/bin/yosys" ] || die "$dir/bin/yosys does not exist."
    [ -x "$dir/bin/z3" ] || die "$dir/bin/z3 does not exist (Verilator uses it for randomize())."

    v="$("$dir/bin/verilator" --version | awk '{ print $2 }')"
    version_ge "$v" "$MIN_VERILATOR" ||
        die "Verilator $v is too old; $MIN_VERILATOR or newer is required."
    info "verilator: $("$dir/bin/verilator" --version)"

    info "yosys:     $("$dir/bin/yosys" --version)"
    info "z3:        $("$dir/bin/z3" --version)"
    # The output goes into a variable before grep: with pipefail, `grep -q`
    # closes the pipe early and yosys would die from SIGPIPE, looking like a
    # failure.
    local help_out
    help_out="$("$dir/bin/yosys" -p "help read_slang" 2>&1 || true)"
    if grep -q "^ *read_slang \\[" <<<"$help_out"; then
        info "sv-elab:   read_slang built into Yosys"
        return
    fi
    help_out="$("$dir/bin/yosys" -m slang -p "help read_slang" 2>&1 || true)"
    if grep -q "^ *read_slang \\[" <<<"$help_out"; then
        info "sv-elab:   read_slang as a plugin (yosys -m slang)"
        return
    fi
    die "the Yosys in this release has no read_slang (sv-elab)."
}

# Builds and runs a minimal testbench with --binary, using $CXX. This proves
# that the compiler, make, perl, coroutines (--timing) and z3 (randomize with
# a constraint) work together on this machine. It runs inside the install's
# temporary directory, which the trap deletes at the end.
smoke_test() {
    local dir="$1" work="$TMP_DIR/smoke"
    mkdir -p "$work"
    cat >"$work/smoke_tb.sv" <<'EOF'
class smoke_txn;
    rand bit [7:0] x;
    constraint c_x { x > 8'd10; x < 8'd20; }
endclass

module smoke_tb;
    smoke_txn t;
    initial begin
        t = new();
        #1;
        if (t.randomize() == 0 || t.x <= 10 || t.x >= 20) $fatal(1, "randomize failed");
        $display("PASS");
        $finish;
    end
endmodule
EOF
    # Verilator always links with -latomic. Without the libatomic package
    # (RHEL/Rocky 9, no root) drop it; x86-64 does not need it (the Makefile
    # does the same).
    local makeflags=(-MAKEFLAGS "CXX=$CXX" -MAKEFLAGS "LINK=$CXX"
        -MAKEFLAGS "PYTHON3=$dir/bin/tabbypy3")
    if ! echo 'int main(){}' | "$CXX" -x c++ - -o /dev/null -latomic 2>/dev/null; then
        makeflags+=(-MAKEFLAGS "CFG_LDLIBS_THREADS=-pthread")
        info "libatomic missing; linking without -latomic"
    fi
    info "testing Verilator with '$CXX' (takes a few seconds)..."
    if ! (
        cd "$work" &&
            PATH="$dir/bin:$PATH" verilator --binary -j 0 --top-module smoke_tb \
                "${makeflags[@]}" smoke_tb.sv >build.log 2>&1 &&
            PATH="$dir/bin:$PATH" ./obj_dir/Vsmoke_tb >run.log 2>&1 &&
            grep -q PASS run.log
    ); then
        tail -n 20 "$work"/build.log "$work"/run.log >&2 || true
        print_compiler_help
        die "Verilator could not build and run a test with '$CXX'."
    fi
    info "Verilator test: ok"
}

# ---------------------------------------------------------------------------
# Main program
# ---------------------------------------------------------------------------

check_host

if [ -d "$FINAL_DIR" ]; then
    info "OSS CAD Suite $DATE already installed in $FINAL_DIR"
    check_tools "$FINAL_DIR"
    exit 0
fi

mkdir -p "$TOOLS_ROOT"

# Temporary directory with a fixed prefix, which `make tools-prune` recognizes
# in case an install is interrupted in a way that keeps the trap from running.
TMP_DIR="$(mktemp -d "$TOOLS_ROOT/.oss-cad-suite-$DATE.tmp.XXXXXX")"
cleanup() { rm -rf -- "$TMP_DIR"; }
trap cleanup EXIT
trap 'echo; die "interrupted; nothing was installed."' INT TERM

if [ -n "$TGZ" ]; then
    [ -f "$TGZ" ] || die "TGZ=$TGZ does not exist."
    info "using local file $TGZ"
    tgz_file="$TGZ"
else
    tgz_file="$TMP_DIR/$TGZ_NAME"
    info "downloading $URL"
    if command -v curl >/dev/null 2>&1; then
        curl -fL --retry 3 --progress-bar -o "$tgz_file" "$URL" ||
            die "download failed. No access to GitHub? Download it on another machine and use TGZ=/path/$TGZ_NAME"
    elif command -v wget >/dev/null 2>&1; then
        wget -q --show-progress -O "$tgz_file" "$URL" ||
            die "download failed. No access to GitHub? Download it on another machine and use TGZ=/path/$TGZ_NAME"
    else
        die "neither curl nor wget found. Use TGZ=/path/$TGZ_NAME"
    fi
fi

info "checking SHA-256..."
actual_sha256="$(sha256sum "$tgz_file" | awk '{ print $1 }')"
if [ "$actual_sha256" != "$EXPECTED_SHA256" ]; then
    die "SHA-256 mismatch.
  expected (tools.lock): $EXPECTED_SHA256
  got:                   $actual_sha256"
fi

info "extracting..."
tar -xzf "$tgz_file" -C "$TMP_DIR"
# Delete the downloaded .tgz (a file passed via TGZ= belongs to the user and stays).
if [ -z "$TGZ" ]; then
    rm -f -- "$tgz_file"
fi

check_tools "$TMP_DIR/oss-cad-suite"
smoke_test "$TMP_DIR/oss-cad-suite"

# Only now does the directory get its final name. A rename within the same
# filesystem is atomic.
mv -T -- "$TMP_DIR/oss-cad-suite" "$FINAL_DIR"
info "installed in $FINAL_DIR"

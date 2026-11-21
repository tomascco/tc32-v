# Bash tab completion for the TC32-V Makefile: `make test <TAB>` lists the
# testbenches, `make lint <TAB>` the RTL modules, `make fpga <TAB>` the FPGA
# designs of the board.
#
# To enable it, add this line to ~/.bashrc (after bash-completion is loaded):
#   source /path/to/tc32-v/scripts/completion/tc32v.bash
#
# Inside a TC32-V checkout it completes the targets and module names by reading
# rtl/, tb/ and fpga/ directly (fast: make is not run). Anywhere else, `make`
# keeps the completion it had before this file was loaded: the usual one from
# bash-completion, or the one of another repository that wraps `make` the same
# way. So several such repositories can be enabled at once, in any order.

# Same rule as the Makefile: only files that already declare a module count.
# /dev/null keeps grep from reading the keyboard when no file is given.
_tc32v_declared() {
    grep -lE '^[[:space:]]*module[[:space:]]' "$@" /dev/null 2>/dev/null
}

_tc32v_make() {
    local cur=${COMP_WORDS[COMP_CWORD]}
    local prev=${COMP_WORDS[COMP_CWORD-1]}

    # Options (-j), variables (SEED=2) and other repositories go to the
    # previous make completion.
    if [[ $cur == -* || $cur == *=* || $prev == = ]] ||
        ! head -n 1 Makefile 2>/dev/null | grep -q '^# TC32-V Makefile'; then
        [[ -n $_tc32v_make_orig ]] && "$_tc32v_make_orig" "$@"
        return
    fi

    # The last verb on the line decides what comes next.
    local word verb=
    for word in "${COMP_WORDS[@]:1:COMP_CWORD-1}"; do
        case $word in test | waves | coverage | debug | lint | synth | schematic | fpga | prog) verb=$word ;; esac
    done

    local candidates f
    case $verb in
    test | waves | coverage | debug)
        # As in the Makefile: tb/ and its subfolders; the name is the file's.
        for f in $(_tc32v_declared $(find tb -name '*_tb.sv' 2>/dev/null)); do
            f=${f##*/}
            f=${f%_tb.sv}
            [[ $f != selfcheck_fail ]] && candidates+=" $f"
        done
        ;;
    lint | synth | schematic)
        # As in the Makefile: rtl/ and its subfolders; the name is the file's.
        for f in $(_tc32v_declared $(find rtl -name '*.sv' -not -path 'rtl/pkg/*' 2>/dev/null)); do
            f=${f##*/}
            candidates+=" ${f%.sv}"
        done
        ;;
    fpga | prog)
        for f in $(_tc32v_declared fpga/"${BOARD:-icesugar-pro}"/*_top.sv); do
            f=${f##*/}
            candidates+=" ${f%_top.sv}"
        done
        ;;
    *)
        # Keep in sync with `make help`.
        candidates="help setup tools tools-prune lint test selfcheck synth waves coverage schematic debug fpga prog clean"
        ;;
    esac

    COMPREPLY=($(compgen -W "$candidates" -- "$cur"))
}

# Loads bash-completion's own make completion now (it is normally loaded on
# first use), so _tc32v_make can fall back to it outside this repository. If
# another script already registered a make completion (for example, one from
# another repository), it is kept and becomes the fallback: loading
# bash-completion's on top of it would erase it.
if ! complete -p make &>/dev/null; then
    _comp_load make 2>/dev/null || __load_completion make 2>/dev/null
fi
_tc32v_spec=$(complete -p make 2>/dev/null)
if [[ $_tc32v_spec =~ -F\ ([^ ]+) && ${BASH_REMATCH[1]} != _tc32v_make ]]; then
    _tc32v_make_orig=${BASH_REMATCH[1]}
fi
unset _tc32v_spec
complete -F _tc32v_make make

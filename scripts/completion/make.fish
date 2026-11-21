# Fish tab completion for the TC32-V Makefile: `make test <TAB>` lists the
# testbenches, `make lint <TAB>` the RTL modules, `make fpga <TAB>` the FPGA
# designs of the board.
#
# To enable it, add this line to ~/.config/fish/config.fish:
#   set -p fish_complete_path /path/to/tc32-v/scripts/completion
#
# Fish then loads this file instead of its own make.fish. Inside a TC32-V
# checkout the targets are read from rtl/, tb/ and fpga/ directly (fast: make
# is not run). Anywhere else, `make` keeps the completion it would have
# without this file.
#
# Fish loads only the FIRST make.fish it finds in $fish_complete_path, so
# another repository that does the same trick would hide this one, or the
# other way around. To let several of them live together, this file first
# loads the NEXT make.fish in the path (another repository's, or fish's own),
# keeps its target lister as a fallback, and only then puts its own on top.
# Each file in the chain answers in its own repository and passes everything
# else down, like the bash version (tc32v.bash).

# Loaded only once, even if fish reads this file again: otherwise the fallback
# below would end up pointing at this file's own lister.
if not set -q __tc32v_make_loaded
    set -g __tc32v_make_loaded 1

    # The next make.fish after this file's folder in $fish_complete_path.
    set -l self_dir (path resolve (path dirname (status current-filename)))
    set -l next_file
    set -l past_self 0
    for dir in $fish_complete_path
        if test $past_self = 1
            if test -f $dir/make.fish
                set next_file $dir/make.fish
                break
            end
        else if test (path resolve $dir) = $self_dir
            set past_self 1
        end
    end

    if set -q next_file[1]
        source $next_file
    else if status get-file completions/make.fish &>/dev/null
        # Fish's own make completion: embedded in the binary since fish 4,
        # a file in $__fish_data_dir before that (found by the loop above,
        # since that folder is in $fish_complete_path).
        status get-file completions/make.fish | source
    end

    # Keeps the previous target lister under another name, to call it outside
    # TC32-V.
    if functions -q __fish_complete_make_targets
        functions -c __fish_complete_make_targets __tc32v_fish_make_targets
    end
end

# Same rule as the Makefile: only files that already declare a module count.
# /dev/null keeps grep from reading the keyboard when no file is given.
function __tc32v_declared
    grep -lE '^[[:space:]]*module[[:space:]]' $argv /dev/null 2>/dev/null
end

# Called by fish's make completion with the whole command line as argument.
function __fish_complete_make_targets
    if not string match -q '# TC32-V Makefile*' -- (head -n 1 Makefile 2>/dev/null)
        functions -q __tc32v_fish_make_targets
        and __tc32v_fish_make_targets $argv
        return
    end

    # The last verb before the word being completed decides what comes next.
    set -l words (commandline -opc)
    set -l verb
    for word in $words[2..]
        if contains -- $word test waves coverage debug lint synth schematic fpga prog
            set verb $word
        end
    end

    switch "$verb"
        case test waves coverage debug
            # As in the Makefile: tb/ and its subfolders; the name is the file's.
            __tc32v_declared (find tb -name '*_tb.sv' 2>/dev/null) |
                string replace -r '^.*/(.*)_tb\.sv$' '$1' |
                string match -v selfcheck_fail | string replace -r '$' \ttestbench
        case lint synth schematic
            # As in the Makefile: rtl/ and its subfolders; the name is the file's.
            __tc32v_declared (find rtl -name '*.sv' -not -path 'rtl/pkg/*' 2>/dev/null) |
                string replace -r '^.*/(.*)\.sv$' '$1\tmodule'
        case fpga prog
            set -l board icesugar-pro
            set -q BOARD; and set board $BOARD
            __tc32v_declared fpga/$board/*_top.sv |
                string replace -r '^.*/(.*)_top\.sv$' '$1\tdesign'
        case '*'
            # Keep in sync with `make help`.
            printf '%s\n' \
                help\t'lists the targets' \
                setup\t'tools, lint and test' \
                tools\t'installs the tools from tools.lock' \
                tools-prune\t'deletes old tool versions' \
                lint\t'lints the RTL [module]' \
                test\t'runs the testbenches [module]' \
                selfcheck\t'a failing assert must fail' \
                synth\t'checks synthesis [module]' \
                waves\t'writes build/<module>.fst and opens Surfer' \
                coverage\t'covergroup report [module]' \
                schematic\t'RTL schematic in the browser [module]' \
                debug\t'lint, synth, schematic, waves and coverage [module]' \
                fpga\t'builds the bitstream [design]' \
                prog\t'programs the board with <design>' \
                clean\t'deletes build/'
    end
end

# Fish tab completion for the TC32-V Makefile: `make test <TAB>` lists the
# testbenches, `make lint <TAB>` the RTL modules.
#
# To enable it, add this line to ~/.config/fish/config.fish:
#   set -p fish_complete_path /path/to/tc32-v/scripts/completion
#
# Fish then loads this file instead of its own make.fish. This file loads
# fish's make.fish first and only changes how the targets are listed: inside a
# TC32-V checkout they are read from rtl/ and tb/ directly (fast: make is not
# run). Anywhere else, `make` keeps its usual completion.

# Fish's own make completion: embedded in the binary since fish 4, a file in
# $__fish_data_dir before that.
if status get-file completions/make.fish &>/dev/null
    status get-file completions/make.fish | source
else if test -f $__fish_data_dir/completions/make.fish
    source $__fish_data_dir/completions/make.fish
end

# Keeps fish's target lister under another name, to call it outside TC32-V.
if functions -q __fish_complete_make_targets
    functions -c __fish_complete_make_targets __tc32v_fish_make_targets
end

# Same rule as the Makefile: only files that already declare a module count.
function __tc32v_declared
    grep -lE '^[[:space:]]*module[[:space:]]' $argv 2>/dev/null
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
        if contains -- $word test waves lint synth
            set verb $word
        end
    end

    switch "$verb"
        case test waves
            __tc32v_declared tb/*_tb.sv | string replace -r '^tb/(.*)_tb\.sv$' '$1' |
                string match -v selfcheck_fail | string replace -r '$' \ttestbench
        case lint synth
            __tc32v_declared rtl/*.sv | string replace -r '^rtl/(.*)\.sv$' '$1\tmodule'
        case '*'
            # Keep in sync with `make help`.
            printf '%s\n' \
                help\t'lists the targets' \
                setup\t'tools, lint and test' \
                tools\t'installs the tools from tools.lock' \
                tools-prune\t'deletes old OSS CAD Suite versions' \
                lint\t'lints the RTL [module]' \
                test\t'runs the testbenches [module]' \
                selfcheck\t'a failing assert must fail' \
                synth\t'checks synthesis [module]' \
                waves\t'writes build/<module>.fst and opens Surfer' \
                clean\t'deletes build/'
    end
end

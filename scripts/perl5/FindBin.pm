# Minimal stand-in for Perl's core FindBin module.
#
# Why it exists: the `verilator` executable is a Perl script that starts with
# `use FindBin`. FindBin ships with Perl, but RHEL/Rocky/Alma 9 split it into a
# separate package (perl-FindBin) that is often missing, and installing it needs
# root. This file covers only what Verilator uses.
#
# It is used only as a fallback: the Makefile and scripts/setup-tools.sh add
# this directory to PERL5LIB only when `perl -MFindBin -e1` fails. Hosts that
# have the real module keep using it.
#
# Exported variables (same meaning as in the real FindBin):
#   $Bin, $Script          directory and name of the script, as invoked
#   $RealBin, $RealScript  the same, after resolving symbolic links
#   $Dir, $RealDir         aliases for $Bin and $RealBin

package FindBin;

use strict;
use warnings;
use Cwd qw(abs_path getcwd);
use File::Basename qw(basename dirname);
use File::Spec;
use Exporter qw(import);

our $VERSION = '1.51';
our @EXPORT_OK = qw($Bin $Script $RealBin $RealScript $Dir $RealDir);
our %EXPORT_TAGS = (ALL => [@EXPORT_OK]);
our ($Bin, $Script, $RealBin, $RealScript, $Dir, $RealDir);

sub init {
    my $script = $0;

    # `perl -e '...'` or a script read from standard input: no file to locate.
    if ($script eq '-e' || $script eq '-') {
        $Bin = $RealBin = $Dir = $RealDir = getcwd();
        $Script = $RealScript = $script;
        return;
    }

    # Invoked by name only (no slash): look for it on the PATH, like the shell.
    if ($script !~ m{/}) {
        for my $dir (File::Spec->path()) {
            my $candidate = File::Spec->catfile($dir, $script);
            if (-f $candidate && -x _) {
                $script = $candidate;
                last;
            }
        }
    }

    $Script = basename($script);
    $Bin = abs_path(dirname($script));

    # Follow the chain of symbolic links to the real file.
    my $real = $script;
    while (-l $real) {
        my $target = readlink($real);
        $real = File::Spec->file_name_is_absolute($target)
            ? $target
            : File::Spec->catfile(dirname($real), $target);
    }
    $RealScript = basename($real);
    $RealBin = abs_path(dirname($real));

    $Dir = $Bin;
    $RealDir = $RealBin;
}

init();

1;

#!/usr/bin/env bash
# Prints the main results of an FPGA build from the nextpnr log: the maximum
# frequency of each clock and how much of the chip the design uses.
#
#   scripts/fpga-summary.sh <nextpnr log> <title>
#
# Exits with code 1 if a clock does not reach its target frequency, so that
# `make fpga` stops before generating the bitstream.

set -euo pipefail

log=$1
title=$2

echo ""
echo "==== $title ===="

# nextpnr prints "Max frequency for clock" twice: an estimate after placement
# and the real value after routing. Only the last one per clock counts. This
# awk exits with 1 if one of those last values is a FAIL.
#   Info: Max frequency for clock '$glbnet$clk$TRELLIS_IO_IN': 188.15 MHz (PASS at 25.00 MHz)
timing_ok=1
awk '
    /Max frequency for clock/ {
        name = $0
        sub(/.*for clock \047/, "", name)
        sub(/\047.*/, "", name)
        # Internal net names: $glbnet$clk$TRELLIS_IO_IN -> clk
        sub(/^\$glbnet\$/, "", name)
        sub(/\$TRELLIS_IO_IN$/, "", name)
        line = $0
        sub(/.*\047: /, "", line)
        last[name] = line
        if (!(name in order)) { order[name] = ++n; names[n] = name }
    }
    END {
        print "Clocks (max frequency, verdict at the target):"
        for (i = 1; i <= n; i++) {
            printf "  %-12s %s\n", names[i], last[names[i]]
            if (last[names[i]] ~ /FAIL/) fail = 1
        }
        if (n == 0) print "  (no clock with a timing constraint)"
        exit fail
    }
' "$log" || timing_ok=0

# Device utilisation table, only the resources that matter most.
#   Info:           TRELLIS_FF:      30/  24288     0%
awk '
    BEGIN {
        label["TRELLIS_COMB"] = "Logic (LUT4)"
        label["TRELLIS_FF"]   = "Flip-flops"
        label["DP16KD"]       = "Block RAM (18 Kbit)"
        label["MULT18X18D"]   = "Multipliers 18x18"
        label["EHXPLLL"]      = "PLL"
        label["TRELLIS_IO"]   = "I/O pins"
        split("TRELLIS_COMB TRELLIS_FF DP16KD MULT18X18D EHXPLLL TRELLIS_IO", keys, " ")
    }
    /Device utilisation:/ { in_table = 1; next }
    in_table && /^Info:[[:space:]]*$/ { in_table = 0 }
    in_table {
        key = $2; sub(/:$/, "", key)
        split($3 $4, used_avail, "/")
        used[key] = used_avail[1]; avail[key] = used_avail[2]; pct[key] = $5
    }
    END {
        print "Utilization:"
        for (i = 1; i <= 6; i++) {
            k = keys[i]
            if (k in used) printf "  %-20s %6s / %-6s %4s\n", label[k], used[k], avail[k], pct[k]
        }
    }
' "$log"

echo "Full log: $log"

if [ "$timing_ok" = 0 ]; then
    echo ""
    echo "ERROR: a clock does not reach its target frequency (FAIL above)."
    exit 1
fi

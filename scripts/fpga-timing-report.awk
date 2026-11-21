# Turns the nextpnr log into a timing report in the spirit of Vivado's
# report_timing_summary: clock summary with slack, then each critical path
# step by step, the RTL lines on it, and the utilization.
#
#   awk -v title="<design> on <board>" -f scripts/fpga-timing-report.awk <nextpnr log>
#
# nextpnr times the design twice: an estimate after placement and the real
# values after routing. Everything timing-related seen before
# "Routing complete" is thrown away, so only the post-route values remain.
#
# The log lines this reads look like:
#   Info: Critical path report for clock '$glbnet$clk$TRELLIS_IO_IN' (posedge -> posedge):
#   Info:   clk-to-q  0.52  0.52 Source u_cnt.q_TRELLIS_FF_Q.Q
#   Info:    routing  0.98  1.50 Net u_cnt.q[0] (51,2) -> (52,2)
#   Info:                          Sink u_cnt.q_TRELLIS_FF_Q_1_DI_CCU2C_S1$CCU2_COMB0.B
#   Info:                          Defined in:
#   Info:                               rtl/tc32v_counter.sv:18.30
#   Info: 2.23 ns logic, 1.11 ns routing
#   Info: Max frequency for clock '$glbnet$clk$TRELLIS_IO_IN': 300.03 MHz (PASS at 25.00 MHz)
#   Info: Max delay posedge $glbnet$clk$TRELLIS_IO_IN -> <async>: 1.76 ns

# Internal net names: $glbnet$clk$TRELLIS_IO_IN -> clk
function clock_name(s) {
    sub(/^\$glbnet\$/, "", s)
    sub(/\$TRELLIS_IO_IN$/, "", s)
    return s
}

# The text between the first pair of single quotes after `from`.
function quoted(s, from) {
    s = substr(s, index(s, from) + length(from))
    sub(/^[^\047]*\047/, "", s)
    sub(/\047.*/, "", s)
    return s
}

function pct(part, whole) {
    return whole > 0 ? sprintf("%.0f%%", 100 * part / whole) : "-"
}

# nextpnr writes a failing clock as "Warning: Max frequency ...".
{ sub(/^(Info|Warning|ERROR): ?/, "") }

/^Routing complete/ {
    # Drops the post-placement estimates.
    n_clocks = 0; n_paths = 0; n_async = 0; n_hist = 0
    delete clock_seen
    post_route = 1
    next
}

# ---- Utilization (printed once, after packing) ----------------------------
/^Device utilisation:/ { in_util = 1; next }
in_util && /^[[:space:]]*$/ { in_util = 0 }
in_util && /:/ {
    # Fields: "TRELLIS_FF:" "31/" "24288" "0%"
    res = $1; sub(/:$/, "", res)
    split($2 $3, ua, "/")
    util_used[res] = ua[1] + 0
    util_avail[res] = ua[2] + 0
    if (!(res in util_order)) { util_order[res] = ++n_util; util_names[n_util] = res }
    next
}

# ---- Critical paths -------------------------------------------------------
/^Critical path report for / {
    p = ++n_paths
    if ($0 ~ /cross-domain/) {
        from = $0; sub(/.*cross-domain path \047/, "", from)
        to = from
        sub(/\047.*/, "", from)
        sub(/^[^\047]*\047 -> \047/, "", to); sub(/\047.*/, "", to)
        split(from, f, " "); split(to, t, " ")
        path_title[p] = clock_name(f[length(f)]) " -> " clock_name(t[length(t)])
        path_clock[p] = ""
    } else {
        c = clock_name(quoted($0, "for clock"))
        edges = $0; sub(/.*\(/, "(", edges); sub(/\):$/, ")", edges)
        path_title[p] = c " -> " c " " edges
        path_clock[p] = c
    }
    path_steps[p] = 0; path_hidden[p] = 0; path_start[p] = ""; path_end[p] = ""; path_rtl[p] = ""
    in_path = 1; in_defined = 0
    next
}
in_path && /^[[:space:]]+type[[:space:]]+curr/ { next }
in_path && /^[[:space:]]*(clk-to-q|logic|routing|setup|hold)[[:space:]]/ {
    in_defined = 0
    path_delay[p] = $3 + 0
    if ($4 == "Source") {
        if (path_start[p] == "") path_start[p] = $5
        path_end[p] = $5
    }
    # Steps of 0.00 ns inside a carry chain (dedicated wires between the
    # halves of a slice and to the next one) only make the table longer.
    if ($2 == "0.00" && ($1 == "logic" || $1 == "routing")) {
        path_hidden[p]++
        next
    }
    s = ++path_steps[p]
    step_type[p, s] = $1
    step_incr[p, s] = $2
    step_total[p, s] = $3
    step_name[p, s] = $5
    step_loc[p, s] = ($4 == "Net" && $7 == "->") ? $6 "->" $8 : ""
    next
}
in_path && /^[[:space:]]+Sink / { path_end[p] = $2; in_defined = 0; next }
in_path && /^[[:space:]]+Defined in:/ { in_defined = 1; next }
in_path && in_defined && /^[[:space:]]+[^[:space:]]/ {
    # Only project files: the cell libraries of the tools come with an
    # absolute path.
    file = $1
    if (file !~ /^\// && index(path_rtl[p], "\n    " file) == 0)
        path_rtl[p] = path_rtl[p] "\n    " file
    next
}
in_path && /^[0-9.]+ ns logic, [0-9.]+ ns routing/ {
    path_logic[p] = $1 + 0
    path_routing[p] = $4 + 0
    in_path = 0; in_defined = 0
    next
}

# ---- Clock summary --------------------------------------------------------
/^Max frequency for clock / {
    c = clock_name(quoted($0, "for clock"))
    rest = $0; sub(/.*\047: /, "", rest)       # 300.03 MHz (PASS at 25.00 MHz)
    split(rest, w, /[ ()]+/)                   # 300.03 MHz PASS at 25.00 MHz
    if (!(c in clock_seen)) { clock_seen[c] = 1; clocks[++n_clocks] = c }
    fmax[c] = w[1] + 0; verdict[c] = w[3]; target[c] = w[5] + 0
    next
}
/^Max delay / {
    line = $0; sub(/^Max delay /, "", line)
    gsub(/\$glbnet\$/, "", line); gsub(/\$TRELLIS_IO_IN/, "", line)
    async[++n_async] = line
    next
}

# ---- Slack histogram ------------------------------------------------------
/^Slack histogram:/ { in_hist = 1; next }
in_hist && /^[[:space:]]*$/ { in_hist = 0; next }
in_hist { hist[++n_hist] = $0; next }

END {
    rule = "--------------------------------------------------------------------------------"
    print "Timing report: " title
    print "Values after routing, from nextpnr-ecp5. Times in ns."
    print ""
    if (!post_route) print "WARNING: no \"Routing complete\" in the log; these are estimates.\n"

    print "Clock summary"
    print rule
    printf "%-14s %12s %12s %10s %10s %8s  %s\n", "clock", "target", "Fmax", "period", "WNS", "verdict", ""
    for (i = 1; i <= n_clocks; i++) {
        c = clocks[i]
        period[c] = target[c] > 0 ? 1000 / target[c] : 0
        crit = fmax[c] > 0 ? 1000 / fmax[c] : 0
        wns[c] = period[c] - crit
        printf "%-14s %8.2f MHz %8.2f MHz %10.3f %10.3f %8s\n", \
            c, target[c], fmax[c], period[c], wns[c], verdict[c]
    }
    if (n_clocks == 0) print "(no clock with a timing constraint)"
    print ""
    print "WNS (worst slack) = period - delay of the worst path. Negative: the clock"
    print "does not reach its target, and `make fpga` stops before the bitstream."
    if (n_async > 0) {
        print ""
        print "Paths to or from I/O pins (no constraint, delay only):"
        for (i = 1; i <= n_async; i++) print "  " async[i]
    }

    for (p = 1; p <= n_paths; p++) {
        print ""
        print "Critical path: " path_title[p]
        print rule
        total = path_delay[p]
        printf "Startpoint: %s\n", path_start[p]
        printf "Endpoint:   %s\n", path_end[p]
        split_total = path_logic[p] + path_routing[p]
        printf "Delay:      %.2f = %.2f logic (%s) + %.2f routing (%s)\n", \
            total, path_logic[p], pct(path_logic[p], split_total), \
            path_routing[p], pct(path_routing[p], split_total)
        c = path_clock[p]
        if (c != "" && period[c] > 0)
            printf "Required:   %.2f (%.2f MHz), slack %.2f\n", period[c], target[c], period[c] - total
        print ""
        printf "  %-9s %6s %7s  %-17s %s\n", "type", "incr", "total", "tile -> tile", "cell pin / net"
        for (s = 1; s <= path_steps[p]; s++)
            printf "  %-9s %6s %7s  %-17s %s\n", step_type[p, s], step_incr[p, s], \
                step_total[p, s], step_loc[p, s], step_name[p, s]
        if (path_hidden[p] > 0)
            printf "  (%d steps of 0.00 ns inside carry chains left out; all of them are in the log)\n", path_hidden[p]
        if (path_rtl[p] != "") {
            print ""
            printf "RTL on this path (file:line.column):%s\n", path_rtl[p]
        }
    }

    print ""
    print "Utilization"
    print rule
    printf "%-14s %8s %8s %6s\n", "resource", "used", "total", "%"
    # The main resources first, always; then any other one in use.
    n_main = split("TRELLIS_COMB TRELLIS_FF DP16KD MULT18X18D EHXPLLL TRELLIS_IO", main, " ")
    for (i = 1; i <= n_main; i++) {
        r = main[i]; is_main[r] = 1
        if (r in util_used)
            printf "%-14s %8d %8d %6s\n", r, util_used[r], util_avail[r], pct(util_used[r], util_avail[r])
    }
    for (i = 1; i <= n_util; i++) {
        r = util_names[i]
        if (util_used[r] > 0 && !(r in is_main))
            printf "%-14s %8d %8d %6s\n", r, util_used[r], util_avail[r], pct(util_used[r], util_avail[r])
    }
    print "TRELLIS_COMB = one LUT4 (+ carry), TRELLIS_FF = one flip-flop."
    print "Resources not used are left out, except the main ones."

    if (n_hist > 0) {
        print ""
        print "Slack histogram (endpoints per slack range)"
        print rule
        for (i = 1; i <= n_hist; i++) print hist[i]
    }
}

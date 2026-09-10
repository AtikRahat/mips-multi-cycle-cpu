## timing_constraints.sdc
## Tells TimeQuest that clk is a real 50MHz clock (period = 20.000 ns).
## Without this, Quartus has no timing constraint on the actual CPU
## clock domain at all - it only reports Fmax for the unrelated
## internal JTAG test clock (altera_reserved_tck), which is why the
## Fmax Summary only showed that one row.

create_clock -name clk -period 20.000 [get_ports {clk}]

derive_clock_uncertainty

## KEY[3:0] are plain async push-buttons, not clocked logic - tell
## the analyzer not to time-constrain paths from them.
set_false_path -from [get_ports {KEY[*]}]
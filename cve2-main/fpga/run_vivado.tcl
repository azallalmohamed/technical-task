set mode [lindex $argv 0]
if {$mode eq ""} { set mode run }
set part xczu1cg-sbva484-1-e
set per  10.0
set outd build/vivado_$mode
file mkdir $outd

set incs {}
set files {}
set fh [open files.f]
foreach l [split [read $fh] "\n"] {
  set l [string trim $l]
  if {$l eq "" || [string match "//*" $l]} continue
  if {[string match "+incdir+*" $l]} { lappend incs [string range $l 8 end]; continue }
  if {[string match "*tracer*" $l] || [string match "*top_tracing*" $l] || [string match "*clock_gate*" $l]} continue
  lappend files $l
}
close $fh
lappend files fpga/cve2_clock_gate_fpga.sv fpga/cve2_fpga_top.sv

read_verilog -sv $files
read_xdc fpga/config.xdc

synth_design -top cve2_fpga_top -part $part -include_dirs $incs -verilog_define SYNTHESIS \
             -flatten_hierarchy rebuilt
opt_design
place_design
phys_opt_design
route_design

report_utilization               -file $outd/utilization.rpt
report_utilization -hierarchical -file $outd/utilization_hier.rpt
report_timing_summary -delay_type max -max_paths 5 -file $outd/timing.rpt
report_power                     -file $outd/power.rpt

set wns  [get_property SLACK [get_timing_paths -max_paths 1 -setup]]
set fmax [expr {1000.0 / ($per - $wns)}]
set fh [open $outd/summary.txt w]
puts $fh "mode=$mode part=$part period_ns=$per WNS_ns=$wns Fmax_est_MHz=$fmax"
close $fh
puts "mode=$mode WNS=$wns ns  Fmax_est=$fmax MHz"
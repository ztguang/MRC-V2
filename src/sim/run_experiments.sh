#!/bin/bash
# Legacy wrapper → full paper experiment runner (4 groups × N, default 10)
exec /root/lunwen/sim/run_paper_experiments.sh "${1:-10}" "${2:-ABCD}"

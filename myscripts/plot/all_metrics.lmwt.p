#!/usr/bin/gnuplot
set terminal png size 400,300 enhanced 20
set xlabel 'LMWT'
set ylabel 'Metric'
plot for[col=1:5] "-" using 1:2 title columnheader(2) with linespoints

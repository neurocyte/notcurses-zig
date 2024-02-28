#include <notcurses/notcurses.h>

#pragma once

int notcurses_getvec_nblock(struct notcurses *n, ncinput *ni, int vcount);

int utf8_egc_len(const char *gcluster, int *colcount);

#include <notcurses/wrappers.h>

int notcurses_getvec_nblock(struct notcurses *n, ncinput *ni, int vcount) {
  struct timespec ts = {.tv_sec = 0, .tv_nsec = 0};
  return notcurses_getvec(n, &ts, ni, vcount);
}

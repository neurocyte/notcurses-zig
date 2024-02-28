#include <notcurses/wrappers.h>

#include <limits.h>
#include <unictype.h>
#include <unigbrk.h>
#include <wchar.h>
#include <wctype.h>

int notcurses_getvec_nblock(struct notcurses *n, ncinput *ni, int vcount) {
  struct timespec ts = {.tv_sec = 0, .tv_nsec = 0};
  return notcurses_getvec(n, &ts, ni, vcount);
}

int utf8_egc_len(const char *gcluster, int *colcount) {
  size_t ret = 0;
  *colcount = 0;
  int r;
  mbstate_t mbt;
  memset(&mbt, 0, sizeof(mbt));
  wchar_t wc, prevw = 0;
  bool injoin = false;
  do {
    r = mbrtowc(&wc, gcluster, MB_LEN_MAX, &mbt);
    if (r < 0) {
      // FIXME probably ought escape this somehow
      // logerror("invalid UTF8: %s", gcluster);
      return -1;
    }
    if (prevw && !injoin && uc_is_grapheme_break(prevw, wc)) {
      break; // starts a new EGC, exit and do not claim
    }
    int cols;
    if (uc_is_property_variation_selector(wc)) { // ends EGC
      ret += r;
      break;
    } else if (wc == L'\u200d' ||
               injoin) { // ZWJ is iswcntrl, so check it first
      injoin = true;
      cols = 0;
    } else {
      cols = wcwidth(wc);
      if (cols < 0) {
        injoin = false;
        if (iswspace(wc)) { // newline or tab
          *colcount = 1;
          return ret + 1;
        }
        cols = 1;
        if (iswcntrl(wc)) {
          // logerror("prohibited or invalid unicode: 0x%08x", (unsigned)wc);
          return -1;
        }
      }
    }
    if (*colcount == 0) {
      *colcount += cols;
    }
    ret += r;
    gcluster += r;
    if (!prevw) {
      prevw = wc;
    }
  } while (r);
  // FIXME what if injoin is set? incomplete EGC!
  return ret;
}

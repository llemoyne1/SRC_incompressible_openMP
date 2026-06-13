# 0337d — one-line livevis status output

When `SRC_LIVE_VIS_LOG_SOURCE=1`, livevis status messages now use carriage-return plus line-clear (`\r\033[K`) and `std::flush`, so repeated updates reuse the same terminal line instead of appending one line per visualization frame.

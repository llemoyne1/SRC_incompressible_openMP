# 0335b — namespace fix for live visualization build

The first 0335a live-visualization implementation included `particle_state.h`, `src_mpcd_base.h`, and GLFW/OpenGL headers while already inside `namespace mpcd`.  With `MPCD_ENABLE_LIVE_VIS=1`, this polluted system headers into `mpcd::std` and produced errors such as `mpcd::std::uint8_t` and `mpcd::std::size_t`.

This fix moves all heavy includes outside `namespace mpcd`, then reopens the namespace only for the live-visualization implementation.

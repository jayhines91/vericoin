// Stub for cross-compiled macOS builds where compiler-rt is unavailable.
// Qt 5.15+ references ___isOSVersionAtLeast (Darwin C symbol for __isOSVersionAtLeast).
int __isOSVersionAtLeast(int major, int minor, int patch)
{
    (void)major;
    (void)minor;
    (void)patch;
    return 1;
}

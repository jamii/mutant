Creates bugs, in order to practice debugging.

(See also <https://en.wikipedia.org/wiki/Mutation_testing>)

```
~/zig$ rg --files lib/std | grep -F '.zig' | zig run ../mutant/mutant.zig

~/zig$ git diff
diff --git a/lib/std/os/linux.zig b/lib/std/os/linux.zig
index ca8f0907e..3ac28c5f5 100644
--- a/lib/std/os/linux.zig
+++ b/lib/std/os/linux.zig
@@ -961,7 +961,7 @@ pub fn sigaction(sig: u6, noalias act: ?*const Sigaction, noalias oact: ?*Sigact
         .sparc, .sparcv9 => syscall5(.rt_sigaction, sig, ksa_arg, oldksa_arg, @ptrToInt(ksa.restorer), mask_size),
         else => syscall4(.rt_sigaction, sig, ksa_arg, oldksa_arg, mask_size),
     };
-    if (getErrno(result) != 0) return result;
+    if (getErrno(result) == 0) return result;

     if (oact) |old| {
         old.handler.handler = oldksa.handler;

~/zig$ zig build test-std
...
Test [883/1944] os.test.test "std-native-Debug-bare-multi sigaction"... FAIL (TestExpectedEqual)
```
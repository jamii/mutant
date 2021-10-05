<https://en.wikipedia.org/wiki/Mutation_testing>

```
~/zig$ rg --files lib/std | grep -F '.zig' | zig run ../mutant/mutant.zig

~/zig$ git diff
diff --git a/lib/std/math/copysign.zig b/lib/std/math/copysign.zig
index 47065feda..47306e238 100644
--- a/lib/std/math/copysign.zig
+++ b/lib/std/math/copysign.zig
@@ -56,7 +56,7 @@ fn copysign128(x: f128, y: f128) f128 {
     const ux = @bitCast(u128, x);
     const uy = @bitCast(u128, y);

-    const h1 = ux & (maxInt(u128) / 2);
+    const h1 = ux & (maxInt(u128) / 0);
     const h2 = uy & (@as(u128, 1) << 127);
     return @bitCast(f128, h1 | h2);
 }
 
~/zig$ zig build test-std
./lib/std/math/copysign.zig:59:35: error: division by zero
    const h1 = ux & (maxInt(u128) / 0);
```
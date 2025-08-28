This is an example of file generation.

If you wish to have the cmdtree built at build time and not at comptime for your program, then this is the example for you.

The `b.addInstallDirectory()` in the build.zig is not necessary.
But with it, `zig build` will create `./zig-out/cmdtree_gen.zig` and you can see what tetra.app_init


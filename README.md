# Zig-Spudde

Starcraft 2 bot for competing on [sc2ai.net](https://sc2ai.net/), written in Zig 0.9.1.

## Running

1. Install [Zig](https://ziglang.org/).
2. Download the bot.
3. In the bot folder write `zig run src/main.zig`.
If you are using VS Code, you can build and launch using the configs in the .vscode folder. Debugging also works.
4. To build a release build write `zig build -Drelease-safe`
5. To build an executable that works on the sc2ai ladder write
`zig build -Dtarget=x86_64-linux -Drelease-safe`

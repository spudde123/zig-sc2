# Zig-sc2

Intended to make a Starcraft 2 bot for competing
on [sc2ai.net](https://sc2ai.net/), written in Zig 0.17.0.
It doesn't at this time use everything in the SC2
[API](https://github.com/Blizzard/s2client-proto),
but nothing important for actually making bots should
be missing.

Start from [zig-sc2-template](https://github.com/spudde123/zig-sc2-template) to make your own bot.

## Replay and rendering APIs

The package exports `sc2p` and `ws` for low-level protocol and WebSocket access.
`WebSocketClient.startReplay()` uses the bot's raw defaults;
`startReplayWithOptions()` accepts explicit interface options, including rendering.
Response data borrows the supplied response allocator and must be consumed or
copied before that allocator is reset.

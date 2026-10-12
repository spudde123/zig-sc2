# Zig-sc2

Intended to make a Starcraft 2 bot for competing
on [sc2ai.net](https://sc2ai.net/), written in Zig 0.17.0.
It doesn't at this time use everything in the SC2
[API](https://github.com/Blizzard/s2client-proto),
but nothing important for actually making bots should
be missing.

Start from [zig-sc2-template](https://github.com/spudde123/zig-sc2-template) to make your own bot.

## Native Linux replay sessions

The package also exports `ReplaySession`, `sc2p`, and `ws` for tools
that need to control playback independently of the bot runner.

`ReplaySession.open(allocator, io, config, response_allocator)` launches a
bootstrap client, reads replay metadata, and relaunches the matching base build
with the replay's data version. Configuration accepts an installation root,
absolute replay path, optional player/port/fog settings, render resolution, and
EGL/OSMesa library paths. Player ID `0` requests the all-player observer view;
`null` selects the first participant. The configuration's fog flag is forwarded
at startup only; observations use the original `getObservation()` method. The
startup flag is not a substitute for choosing perspective 0 for RGB visibility
(verified on SC2 4.10). It always starts replays with `realtime=false`.

Use `session.observe()`, `session.advance(count)`, and
`session.client.moveObserverCamera(x, y)`. RGB images are in
`response.observation.?.render.?.map` / `.minimap`. The `ImageData.image` slices
borrow the response allocator: copy/consume before resetting its arena. Use a
persistent arena for `allocator` (metadata strings last for the session), and
call `session.close()` to close the socket and terminate/reap the owned process.
Blocking I/O supports Zig `std.Io` cancellation.

Existing `WebSocketClient.startReplay()` still uses the bot's raw defaults;
`startReplayWithOptions()` accepts explicit interface options. Protocol-only
render tests require neither SC2 nor a display: `zig build test-render`.

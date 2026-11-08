# Playback regression (0.4.2)

The player used to evaluate `filtered.map(\.id)` in the root `ContentView`'s
`onChange` modifier on every view update, even while the library was hidden.
With 1,131 games this re-ran title recognition and localized sorting. Controller
buttons/axes published to the same root view, turning ordinary gameplay input
into repeated expensive catalog queries. The emulation queue kept running at
60 FPS while the main-thread display link and input timer starved.

On the development M4 Mac, the same hosted-window test before/after the fix gave:

| Measurement | Before | After |
| --- | ---: | ---: |
| Median playback body evaluation | 147.24 ms | 0.05 ms |
| Core frames submitted per second | 60.19 | 60.12 |
| Window frames submitted per second | 3.46 | 59.87 |
| Controller input updates per second | 6.06 | 60.00 |
| Longest presentation interval | 571.21 ms | 17.07 ms |

The browser selection observer now lives inside `libraryView`, so it is absent
during playback. Gameplay buttons and axes continue to feed the core directly;
the controller UI only publishes connection metadata unless the diagnostics
panel is open. The HUD reports both presentation and core rates.

The final regression also launches Snow Bros., Battle City and Super Mario Bros.
in isolated save directories, with continuous simulated input on both ports.
All three passed (58.6–59.6 window submissions/s, 59.0–60.0 input updates/s,
95th-percentile presentation interval approximately 16.7 ms). A presentation
counter measures submissions to the window layer, not physical panel scanout.

Run `zsh scripts/build_playback_test.sh`, then open the resulting
`build/PlaybackPerformance.app`. The test exits automatically and writes
`build/playback-performance-report.json`. The full library and downloaded cores
are required. It does not touch the user's library or saves.

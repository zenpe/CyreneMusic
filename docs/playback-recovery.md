# Playback recovery boundaries

The service owns user intent and queue navigation. `EngineHost` owns serialized
source mutations. The engine owns its native player, event attribution and
bounded native cleanup. Recovery must not create a second competing owner.

## Natural playlist advancement

An item becoming selected is not proof that it is ready. JustAudioEngine emits
a pending-source event for a selected prepared item, then commits its generation
only when ready. During this interval the service suspends old-track liveness
checks and preloading, preserves the old presentation timeline, and shows
buffering without disabling playback controls.
Seeking is disabled only while that native source transition is pending, including
when paused. Ordinary buffering of the displayed track remains seekable.

The natural transition has an eight-second deadline while playing. Pausing
cancels that deadline; resuming starts observation again. Failure is attributed
to the selected item's generation and handled by the existing bounded candidate
coordinator. Before reporting a natural-transition timeout, the engine detaches
the failed player and stops/disposes it using the bounded cleanup path, preventing
it from becoming audible later. Cleanup captures only that old instance; a newer
selection or transport intent suppresses the delayed failure report. A failed
item cannot subsequently commit through a late ready event.
This deadline is separate from the subsequent recovery navigation budget.

## Foreground control and cancellation

A newer foreground transaction revokes an outstanding JustAudio load immediately.
Cancellation releases Dart's wait, but the host does **not** start a concurrent
source mutation: the engine first stops the old load using the official API.
Stop is bounded by the native control timeout; an unsettled old load is isolated
by disposing its player with the existing cleanup deadline. Cancellation is not
a guarantee of immediate native teardown or instant playback.
Players whose initialization was cancelled before all event subscriptions were
attached are always disposed, even when their pending native operation settles.

Pause intent can reach just_audio while loading without waiting for the source
queue. It also prevents deferred autoplay. A failed native pause is reported as
a control failure, never swallowed as a successfully cancelled load. Native abort
callbacks during cancellation cannot trigger a second recovery.

## Recovery and budgets

- Android forwards HTTP status or Media3 error codes through the existing error
  channel. URL refresh policy can distinguish expired/absent resources from
  rate limiting or decoder errors. HTTP 429 stops candidate scanning.
- Automatic navigation retains its twelve-second budget and maximum of three
  candidate attempts. Remote resolution shares remaining time among candidates,
  reserving three seconds for native loading. Local/cache hits remain eligible.
  Manual selection budgets are unchanged. Three successful probes are not
  guaranteed when network or native loading consumes the available budget.
- A transient background resolution failure may retry once after two seconds.
  Pause, new selection, changed source/quality or queue invalidation cancels that
  scheduled retry. Empty/rejected responses do not create repeated background
  requests. A failed attempt is never recorded as a successful preload.
- Buffering and play/pause intent are orthogonal. The media session reports
  buffering while retaining intent; the progress indicator does not intercept
  taps. Desktop MediaKit retains its existing native loading/control path.

Regression coverage lives in `just_audio_resume_test.dart`,
`playback_navigation_recovery_test.dart`, `playback_transition_coordinator_test.dart`,
`media_transport_state_test.dart` and `playback_switch_ring_test.dart`. Native
error propagation is covered by `PlaybackErrorCodeTest` in the vendored adapter.

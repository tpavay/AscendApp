// A child that stays alive doing nothing, so `runSeedStep` has a real wedge to
// kill. The timer matters: with a bare `await new Promise(() => {})` Node spots
// the unsettled top-level await and exits 13 on its own, which is not the case
// being tested. A wedged seed holds its event loop open through the Firestore
// client's own timers, exactly like this.
setInterval(() => {}, 1_000);

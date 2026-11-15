# app/loop.lua

The loop between the core, the adapters and the UI.

- [ ] When an event arrives, the loop can pass it to the core and carry out the returned effects in order.
- [ ] When an effect asks for information, the loop can pass the answer back to the core as an event.
- [ ] When an effect fails, the loop can pass the failure back to the core as an event and keep running.

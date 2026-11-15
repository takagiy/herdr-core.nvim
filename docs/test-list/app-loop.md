# app/loop.lua

The loop between the core, the adapters and the UI.

- [x] When an event arrives, the loop can pass it to the core and carry out the returned effects in order.
- [x] When an effect asks for information, the loop can pass the answer back to the core as an event.
- [x] When an effect fails, the loop can pass the failure back to the core as an event and keep running.
- [x] When the event stream from the core closes, the loop can follow it again after a short wait.
- [x] When the event stream keeps closing right away, the loop can wait longer each time before following it again.

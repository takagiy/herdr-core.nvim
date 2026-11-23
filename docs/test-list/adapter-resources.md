# adapter/resources.lua

The monitors of the resources: armed and disarmed as the core asks, with what they notify passed to the core.

- [x] When the core asks to arm a monitor, the adapter can make one instance for the element and arm it with the element; asked again, it can arm the same instance with the same notify.
- [x] When monitors notify, the adapter can pass what they listed to the core in one event, on the main loop.
- [x] When a monitor is disarmed, the adapter can call its disarm once and ignore what it notifies afterwards.
- [x] When a monitor cannot be made, fails to arm, or notifies something that cannot be shown, the adapter can report it once and go on; it can still disarm a monitor whose arm failed.

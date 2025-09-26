# OnyInterrupts

OnyInterrupts is a lightweight World of Warcraft: Wrath of the Lich King (3.3.5) combat log assistant that highlights interrupts, crowd control breaks, and failed attempts in the chat frame. It was written for raid environments where you want instant, easy-to-read feedback on who stopped (or failed to stop) a cast.

## Features
- Reports successful spell interrupts and CC-based cast breaks with clickable spell links.
- Highlights failures such as line-of-sight or "used while not casting" attempts, using distinct chat colors for quick scanning.
- Recognizes a wide catalog of class, pet, and racial interrupts, as well as stun- or silence-based cast breaks.
- Remembers the most recent ability per attacker/target pair to fill in missing spell names with a generic **[Interrupt]** label when private server logs omit the data.
- Debounces duplicate "used while not casting" messages for 1.5 seconds after a genuine interrupt is detected on the same target, reducing spam.

## Slash Commands
The addon exposes a single slash command with two aliases:

```text
/onyints
/onyinterrupts
```

Running the command without arguments prints the current verbosity along with a short help message.

## Verbosity Modes
OnyInterrupts stores its settings in the `OnyInterruptsDB` saved variable and supports three verbosity levels:

| Command argument | Mode key | Description |
| --- | --- | --- |
| `all`, `full`, `default` | `all` | Show every interrupt-related event that the addon detects. |
| `self`, `mine`, `me` | `self` | Only report events triggered by your character. |
| `minimal`, `quiet`, `silent` | `minimal` | Report only your successful interrupts and CC-based cast breaks. |

Switch modes with `/onyints <argument>`. For example, `/onyints self` limits the output to interrupts you personally caused.

## Saved Variables
The chosen verbosity is remembered between sessions via the `OnyInterruptsDB` saved variable. Delete that table (or remove the saved variables file) to reset the addon to its default `all` mode.

## Installation
1. Copy the `OnyInterrupts` folder into your `Interface/AddOns` directory.
2. Ensure `OnyInterrupts` is enabled in the in-game AddOns list on the character select screen.
3. Enter the game and optionally adjust the verbosity with `/onyints`.

Enjoy clearer interrupt callouts without the spam!

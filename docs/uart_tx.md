# UART TX (`tc32v_uart_tx`)

Design specification for the UART transmitter, written before the RTL. Items marked
**Open** are decisions not yet made.

## Protocol

8N1 frame, 10 bits, sent one bit time each:

| Bit index | 0     | 1 to 8                    | 9    |
|-----------|-------|---------------------------|------|
| Content   | start | data, LSB first           | stop |
| Value     | 0     | `d[0]` ... `d[7]`         | 1    |

Between frames the line is idle at 1. The stop bit has the same value as idle, but it is
mandatory: it guarantees a high level before the falling edge of the next start bit.

## Interface

| Port     | Dir | Meaning |
|----------|-----|---------|
| `clk`    | in  | clock |
| `rst`    | in  | synchronous reset, active high |
| `d[7:0]` | in  | byte to send. Captured when `start` is accepted; it may change afterwards. |
| `start`  | in  | send request. Accepted only in IDLE. If held high, the module sends again as soon as it returns to IDLE. |
| `tx`     | out | serial line |
| `busy`   | out | 1 while sending. **Open:** register of its own, or derived from the state? |

## Constants

217 clock cycles per bit (25 MHz / 115200 baud = 217.01, error 0.0064%). The baud counter
goes from 0 to 216.

Later: parameters for clock frequency and baud rate, a `localparam` for cycles per bit,
`$clog2` for the counter width, and an elaboration-time check that rejects a large baud
error.

## Status signals

Combinational comparisons on the datapath, read by the FSM. Not registers.

| Signal     | 1 when |
|------------|--------|
| `bit_end`  | baud counter == 216 |
| `last_bit` | bit counter == 9 |

## FSM

Two states, reset to IDLE.

| State   | Condition                 | Next    |
|---------|---------------------------|---------|
| IDLE    | `start`                   | SENDING |
| SENDING | `last_bit` and `bit_end`  | IDLE    |
| any     | otherwise                 | same    |

## Datapath registers

| Register       | Width | Reset    | `start` accepted | In SENDING | Otherwise |
|----------------|-------|----------|------------------|------------|-----------|
| shift register | 10    | all 1s   | load the frame (**Open:** bit order) | on `bit_end`: shift, a 1 enters (**Open:** direction) | hold |
| baud counter   | 8     | 0        | 0                | +1 every cycle; 216 → 0 | hold (IDLE) |
| bit counter    | 4     | 0        | 0                | on `bit_end`: +1 | hold |

Check for the open items: load `'A'` (0x41) on paper, shift 10 times and confirm that `tx`
shows the bits in the order of the protocol table.

## Outputs

- `tx`: the end bit of the shift register, wired directly (no extra register). Filling
  with 1s and resetting to all 1s keeps `tx` at 1 in idle without extra logic.
- `busy`: see the interface table.

## Invariants (future SVA, in `sva/` with `bind`)

- In IDLE, the baud counter is 0. (It resets to 0 and wraps to 0 at the end of the stop
  bit, the same edge on which the FSM enters IDLE.)

## From spec to RTL

Each table above maps to one part of the code:

- each status signal → one combinational assignment;
- the FSM table → the state `always_ff`;
- each datapath register → its own `always_ff`, or a `tc32v_counter` instance whose `en`
  and `rst` are combinational.

If a line of code has no row in this spec, or a row has no code, something is missing.

# Alphabet

## About The Application

This is an example application that takes "votes" for different letters of the alphabet and keeps a running total of the votes received for each letter. For each incoming message, it sends out a message with the total votes for that letter. It uses state partitioning to distribute the votes so that they can be processed in parallel; the letter serves as the partitioning key, so, for example, all votes for the letter "A" are handled by the same partition.

### Input

The inputs to the "Alphabet" application are the letter receiving the vote followed by a 32-bit integer representing the number of votes for this message, with the whole thing encoded in the [source message framing protocol](/book/core-concepts/decoders-and-encoders.md#framed-message-protocols#source-message-framing-protocol). Here's an example input message, written as a Go string:

```
"\x00\x00\x00\x05A\x00\x00\x15\x34"
```

`\x00\x00\x00\x05` -- four bytes representing the number of bytes in the payload
`A` -- a single byte representing the letter "A", which is receiving the votes
`\x00\x00\x15\x34` -- the number `0x1534` (`5428`) represented as a big-endian 32-bit integer

### Output

The messages are strings terminated with a newline, with the form `LETTER => VOTES` where `LETTER` is the letter and `VOTES` is the number of votes for said letter. Each incoming message generates one output messages.

### Processing

The `Decoder`'s `Decode(...)` method creates a `Votes` object with the letter being voted on and the number of votes it is receiving with this message. The `Votes` object is passed with the `AddVotes` state computation to the state object that handles the letter being voted on, and the `AddVotes` function modifies the state to record the new total number of votes 
for the letter. It then creates an `AllVotes` message, which is sent to `Encoder`'s `Encode(...)` method, which converts it into an outgoing message.

## Building Alphabet

In the alphabet directory, run `make`.

## Running Alphabet

In order to run the application you will need Giles Sender, Data Receiver, and the Cluster Shutdown tool. To build them, please see the [Linux](/book/go/getting-started/linux-setup.md) or [MacOS](/book/go/getting-started/macos-setup.md) setup instructions.

You will need four separate shells to run this application. Open each shell and go to the `examples/go/alphabet` directory.

### Shell 1

Run `data_receiver` to listen for TCP output on `127.0.0.1` port `7002`:

```bash
../../../utils/data_receiver/data_receiver --listen 127.0.0.1:7002
```

### Shell 2

```bash
./alphabet --in 127.0.0.1:7010 --out 127.0.0.1:7002 \
  --metrics 127.0.0.1:5001 --control 127.0.0.1:6000 \
  --data 127.0.0.1:6001 --cluster-initializer \
  --external 127.0.0.1:6002 --ponythreads=1 --ponynoblock
```

### Shell 3

Send messages:

```bash
../../../giles/sender/sender --host 127.0.0.1:7010 \
  --file votes.msg --batch-size 50 --interval 10_000_000 \
  --messages 1000000 --binary --msg-size 9 --repeat --ponythreads=1 \
  --ponynoblock --no-write
```

## Shutdown

You can shut down the cluster with this command at any time:

```bash
../../../utils/cluster_shutdown/cluster_shutdown 127.0.0.1:6002
```

You can shut down Giles Sender and Data Receiver by pressing `Ctrl-c` from their respective shells.

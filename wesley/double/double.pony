use ".."

actor Main
  new create(env: Env) =>
    VerifierCLI[DoubleSentMessage val, DoubleReceivedMessage val]
      .run(env, DoubleResultMapper, DoubleSentParser, DoubleReceivedParser)

class DoubleSentMessage
  let ts: U64
  let v: I64

  new val create(ts': U64, v':I64) =>
    ts = ts'
    v = v'

  fun string(fmt: FormatSettings = FormatSettingsDefault): String iso^ =>
    ("(" + ts.string() + ", " + v.string() + ")").clone()

class DoubleReceivedMessage
  let ts: U64
  let v: I64

  new val create(ts': U64, v':I64) =>
    ts = ts'
    v = v'

  fun string(fmt: FormatSettings = FormatSettingsDefault): String iso^ =>
    ("(" + ts.string() + ", " + v.string() + ")").clone()

class DoubleSentParser is SentParser[DoubleSentMessage val]
  let _messages: Array[DoubleSentMessage val] = 
    Array[DoubleSentMessage val]

  fun ref apply(value: Array[String] ref): None ? =>
    let timestamp = value(0).clone().strip().u64()
    let i = value(1).clone().strip().i64()
    _messages.push(DoubleSentMessage(timestamp, i))

  fun ref sent_messages(): Array[DoubleSentMessage val] =>
    _messages

class DoubleReceivedParser is ReceivedParser[DoubleReceivedMessage val]
  let _messages: Array[DoubleReceivedMessage val] = 
    Array[DoubleReceivedMessage val]

  fun ref apply(value: Array[String] ref): None ? =>
    let timestamp = value(0).clone().strip().u64()
    let i = value(1).clone().strip().i64()
    _messages.push(DoubleReceivedMessage(timestamp, i))

  fun ref received_messages(): Array[DoubleReceivedMessage val] =>
    _messages

class DoubleResultMapper 
  is ResultMapper[DoubleSentMessage val, DoubleReceivedMessage val]

  fun sent_transform(sent: Array[DoubleSentMessage val]): CanonicalForm =>
    var results = ResultsList[I64]

    for m in sent.values() do
      results.add(m.v * 2)
    end
    results

  fun received_transform(received: Array[DoubleReceivedMessage val]): 
    CanonicalForm =>
    var results = ResultsList[I64]

    for m in received.values() do
      results.add(m.v)
    end
    results

use "collections"
use "buffy"
use "buffy/messages"
use "buffy/metrics"
use "buffy/topology"
use "net"
use "buffy/sink-node"

actor Main
  new create(env: Env) =>
    try
      let topology: Topology val = recover val
        Topology
          .new_pipeline[String, WordCount val](P, S, recover [0] end)
          .to_map[WordCount val](
            lambda(): MapComputation[String, WordCount val] iso^ => Split end)
          .to_stateful_partition[WordCount val, WordCountTotals](
            recover
              StatePartitionConfig[WordCount val, WordCount val, WordCountTotals](
                lambda(): Computation[WordCount val, Count val] iso^
                  => GenerateCount end,
                lambda(): WordCountTotals => WordCountTotals end,
                FirstLetterPartition, 0)
            end
            )
          .build()
      end
      let sink_builders = recover Array[SinkNodeStepBuilder val] end
      let ui_sink_builder = SinkNodeConfig[Map[String, U64]](
        lambda(): SinkCollector[Map[String, U64]] => 
          WordCountSinkCollector end,
        WordCountSinkConnector,
        WordCountSinkStringify
      )
      sink_builders.push(ui_sink_builder)
      Startup(env, topology, 1, consume sink_builders)
    else
      env.out.print("Couldn't build topology")
    end

class Split is MapComputation[String, WordCount val]
  let punctuation: String = """!"#$%&'()*+,-./:;<=>?@[\]^_`{|}~"""

  fun name(): String => "split"
  fun apply(d: String): Seq[WordCount val] =>
    let counts: Array[WordCount val] iso = recover Array[WordCount val] end
    for word in d.split(" ").values() do
      counts.push(WordCount(_clean(word), 1))
    end
    consume counts

  fun _clean(s: String): String =>
    let clone: String iso = recover s.clone() end
    let punc = punctuation
    recover clone.lower().strip(punc) end

class GenerateCount is Computation[WordCount val, Count val]
  fun name(): String => "count"
  fun apply(wc: WordCount val): Count val =>
    Count(wc)

class Count is StateComputation[WordCount val, WordCountTotals]
  let _word_count: WordCount val

  new val create(wc: WordCount val) =>
    _word_count = wc

  fun apply(state: WordCountTotals, output: MessageTarget[WordCount val] val)
    : WordCountTotals =>
    output(state(_word_count))
    state

class WordCount
  let word: String
  let count: U64
  
  new val create(w: String, c: U64) =>
    word = w
    count = c

class WordCountTotals
  let words: Map[String, U64] = Map[String, U64]

  fun ref apply(value: WordCount val): WordCount val =>
    try
      words(value.word) = words(value.word) + value.count
      WordCount(value.word, words(value.word))
    else
      words(value.word) = value.count
      value
    end

class FirstLetterPartition is PartitionFunction[WordCount val]
  fun apply(wc: WordCount val): U64 =>
    try wc.word(0).hash() else 0 end

class P
  fun apply(s: String): String =>
    s

class S
  fun apply(input: WordCount val): String =>
    input.word + "," + input.count.string()

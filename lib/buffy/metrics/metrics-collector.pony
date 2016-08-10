use "collections"
use "net"
use "json"
use "buffy/messages"
use "buffy/flusher"
use "sendence/epoch"
use "sendence/hub"

actor JsonAccumulator
  let _output: MetricsOutputActor tag
  let _event: String
  let _topic: String
  let _pretty_print: Bool
  var j: JsonArray iso^ = JsonArray(100)

  new create(event: String, topic: String, pretty_print: Bool=false,
    output: MetricsOutputActor tag)
  =>
    _output = output
    _event = event
    _topic = topic
    _pretty_print = pretty_print

  be append(j': JsonArray iso^) =>
    j.data.concat(j'.data.values())

  be flush() =>
    _output(HubJson.payload(_event, _topic, consume j, _pretty_print))

actor TimelineCollector
"""
An actor responsible for collecting Timelines from a single step, node, or
sink's MetricsRecorder
"""
  var timelines: Array[Timeline iso] iso = recover
    Array[Timeline iso](10) end
  let _show_empty: Bool

  new create(show_empty: Bool=false) =>
    _show_empty = show_empty

  be apply(t: Timeline iso) =>
  """
  Add a new Timeline to the local collection
  """
    timelines.push(t)

  be flush(collectors: Iterator[TimelineCollector tag],
    output: JsonAccumulator tag)
  =>
    t' = timelines = recover Array[Timeline iso](10) end
    for tl in t'.values() do
      try
        output.append(tl.json(_show_empty))
      end
    end
    if collectors.has_next() then
      let tl = collectors.next()
      tl.flush(collectors, output)
    else
      output.flush()
    end

actor MetricsCollector is FlushingActor
  let _stdout: StdStream
  let _stderr: StdStream
  let _auth: AmbientAuth
  let _node_name: String
  let _timelines: Array[TimelineCollector tag] iso = recover
    Array[TimelineCollector tag](50) end
  let _event: String
  let _topic: String
  let _pretty_print: Bool = true
  var _output: (MetricsOutputActor tag | None)

  new create(stdout: StdStream,
    stderr: StdStream,
    auth: AmbientAuth,
    node_name: String,
    app_name: String,
    metrics_host: (String | None) = None,
    metrics_service: (String | None) = None,
    period: U64 = 1_000_000_000,
    flush_period: U64 = 1_000_000_000)
  =>
    _stdout = stdout
    _stderr = stderr
	  _auth = auth
    _node_name = node_name
    _app_name = app_name
    _event = "metrics"
    _topic = String(50)
    _topic.append("metrics:")
    _topic.append(_app_name)

    // Create connections and actors here

    // MonitoringHub Output:
    match (metrics_host, metrics_service)
    | (let host: String, let service: String) =>
      let notifier: TCPConnectionNotify iso =
        recover MonitoringHubConnectNotify(stdout, stderr) end
      let conn' = TCPConnection(auth, consume notifier, host, service)
      _output = MonitoringHubOutput(stdout, stderr, conn', app_name)
      // start a timer to flush the metrics-collection
      Flusher(this, flush_period)
    end

  be finished() =>
    _flush()

  be flush() => _flush()

  fun _flush() =>
    let j: JsonAccumulator tag = recover JsonAccumulator(_event, _topic,
      _pretty_print, _output) end
    let collectors = timelines.values()
    let tl = collectors.next()
    tl.flush(collectors, j)

  be add_collector(t: TimelineCollector tag) =>
  """
  Save a tag to TimelineCollector to the local collection
  """
    _timelines.push(t)


class MetricsReporter
	let _id: U64
  let _name: String
  let _catgeory: String
  let _period: U64
  let _timelinecollector: TimelineCollector tag
  var _timeline: Timeline iso

	new val create(id: U64, name: String, category: String,
    period: U64=1_000_000_000, metrics_collector: MetricsCollector tag)
  =>
		_step_id = id
    _step_name = name
    _category = category
    _period = period
    _show_empty = show_empty
    _timelinecollector = TimelineCollector
    metrics_collector.add_collector(_timelinecollector)
    _timeline = recover Timeline(_name, _category, _period) end

  fun ref report(start_time: U64, end_time: U64) =>
    apply(start_time, end_time)

	fun ref apply(start_time: U64, end_time: U64) =>
    _timeline(start_time, end_time)
    if _timeline.size() > 1 then flush() end

  fun ref flush() =>
  """
  Flush the current Timeline to the TimelineCollector
  """
    let t = _timeline = recover Timeline(_name, _category, _period) end
    _timelinecollector(consume t)


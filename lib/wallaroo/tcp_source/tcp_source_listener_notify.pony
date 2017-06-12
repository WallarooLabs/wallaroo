use "net"
use "wallaroo/fail"
use "wallaroo/metrics"
use "wallaroo/topology"
use "wallaroo/recovery"

trait val SourceBuilder
  fun name(): String
  fun apply(event_log: EventLog, auth: AmbientAuth, target_router: Router val):
    TCPSourceNotify iso^
  fun val update_router(router: Router val): SourceBuilder val

class val _SourceBuilder[In: Any val] is SourceBuilder
  let _app_name: String
  let _worker_name: String
  let _name: String
  let _runner_builder: RunnerBuilder val
  let _handler: FramedSourceHandler[In] val
  let _router: Router val
  let _metrics_conn: MetricsSink
  let _pre_state_target_id: (U128 | None)
  let _metrics_reporter: MetricsReporter

  new val create(app_name: String, worker_name: String,
    name': String,
    runner_builder: RunnerBuilder val,
    handler: FramedSourceHandler[In] val,
    router: Router val, metrics_conn: MetricsSink,
    pre_state_target_id: (U128 | None) = None,
    metrics_reporter: MetricsReporter iso)
  =>
    _app_name = app_name
    _worker_name = worker_name
    _name = name'
    _runner_builder = runner_builder
    _handler = handler
    _router = router
    _metrics_conn = metrics_conn
    _pre_state_target_id = pre_state_target_id
    _metrics_reporter = consume metrics_reporter

  fun name(): String => _name

  fun apply(event_log: EventLog, auth: AmbientAuth, target_router: Router val):
    TCPSourceNotify iso^
  =>
    FramedSourceNotify[In](_name, auth, _handler, _runner_builder, _router,
      _metrics_reporter.clone(), event_log, target_router, _pre_state_target_id)

  fun val update_router(router: Router val): SourceBuilder val =>
    _SourceBuilder[In](_app_name, _worker_name, _name, _runner_builder,
      _handler, router, _metrics_conn, _pre_state_target_id,
      _metrics_reporter.clone())

interface val SourceBuilderBuilder
  fun name(): String
  fun apply(runner_builder: RunnerBuilder val, router: Router val,
    metrics_conn: MetricsSink, pre_state_target_id: (U128 | None) = None,
    worker_name: String,
    metrics_reporter: MetricsReporter iso):
      SourceBuilder val

class val TypedSourceBuilderBuilder[In: Any val]
  let _app_name: String
  let _name: String
  let _handler: FramedSourceHandler[In] val

  new val create(app_name: String, name': String,
    handler: FramedSourceHandler[In] val)
  =>
    _app_name = app_name
    _name = name'
    _handler = handler

  fun name(): String => _name

  fun apply(runner_builder: RunnerBuilder val, router: Router val,
    metrics_conn: MetricsSink, pre_state_target_id: (U128 | None) = None,
    worker_name: String, metrics_reporter: MetricsReporter iso):
      SourceBuilder val
  =>
    _SourceBuilder[In](_app_name, worker_name,
      _name, runner_builder, _handler, router,
      metrics_conn, pre_state_target_id, consume metrics_reporter)

interface TCPSourceListenerNotify
  """
  Notifications for TCPSource listeners.
  """
  fun ref listening(listen: TCPSourceListener ref) =>
    """
    Called when the listener has been bound to an address.
    """
    None

  fun ref not_listening(listen: TCPSourceListener ref) =>
    """
    Called if it wasn't possible to bind the listener to an address.
    """
    None

  fun ref connected(listen: TCPSourceListener ref): TCPSourceNotify iso^ ?
    """
    Create a new TCPSourceNotify to attach to a new TCPSource for a
    newly established connection to the server.
    """

  fun ref update_router(router: Router val)

class SourceListenerNotify is TCPSourceListenerNotify
  var _source_builder: SourceBuilder val
  let _event_log: EventLog
  let _target_router: Router val
  let _auth: AmbientAuth

  new iso create(builder: SourceBuilder val, event_log: EventLog, auth: AmbientAuth,
    target_router: Router val) =>
    _source_builder = builder
    _event_log = event_log
    _target_router = target_router
    _auth = auth

  fun ref listening(listen: TCPSourceListener ref) =>
    @printf[I32]((_source_builder.name() + " source is listening\n").cstring())

  fun ref not_listening(listen: TCPSourceListener ref) =>
    @printf[I32](
      (_source_builder.name() + " source is unable to listen\n").cstring())
    Fail()

  fun ref connected(listen: TCPSourceListener ref): TCPSourceNotify iso^ =>
    _source_builder(_event_log, _auth, _target_router)

  fun ref update_router(router: Router val) =>
    _source_builder = _source_builder.update_router(router)

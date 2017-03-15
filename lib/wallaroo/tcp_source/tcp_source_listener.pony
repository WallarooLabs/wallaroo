use "collections"
use "wallaroo/boundary"
use "wallaroo/metrics"
use "wallaroo/resilience"
use "wallaroo/routing"
use "wallaroo/tcp_sink"
use "wallaroo/topology"

class TCPSourceListenerBuilder
  let _source_builder: SourceBuilder val
  let _router: Router val
  let _router_registry: RouterRegistry
  let _route_builder: RouteBuilder val
  let _default_in_route_builder: (RouteBuilder val | None)
  let _outgoing_boundaries: Map[String, OutgoingBoundary] val
  let _tcp_sinks: Array[TCPSink] val
  let _alfred: Alfred
  let _auth: AmbientAuth
  let _default_target: (Step | None)
  let _target_router: Router val
  let _host: String
  let _service: String
  let _metrics_reporter: MetricsReporter

  new val create(source_builder: SourceBuilder val, router: Router val,
    router_registry: RouterRegistry, route_builder: RouteBuilder val,
    outgoing_boundaries: Map[String, OutgoingBoundary] val,
    tcp_sinks: Array[TCPSink] val,
    alfred: Alfred tag,
    auth: AmbientAuth,
    default_target: (Step | None) = None,
    default_in_route_builder: (RouteBuilder val | None) = None,
    target_router: Router val = EmptyRouter,
    host: String = "", service: String = "0",
    metrics_reporter: MetricsReporter iso)
  =>
    _source_builder = source_builder
    _router = router
    _router_registry = router_registry
    _route_builder = route_builder
    _default_in_route_builder = default_in_route_builder
    _outgoing_boundaries = outgoing_boundaries
    _tcp_sinks = tcp_sinks
    _alfred = alfred
    _auth = auth
    _default_target = default_target
    _target_router = target_router
    _host = host
    _service = service
    _metrics_reporter = consume metrics_reporter

  fun apply(): TCPSourceListener =>
    let tcp_l = TCPSourceListener(_source_builder, _router, _router_registry,
      _route_builder, _outgoing_boundaries, _tcp_sinks, _alfred, _auth,
      _default_target, _default_in_route_builder, _target_router, _host,
      _service where metrics_reporter = _metrics_reporter.clone())
    _router_registry.register_partition_router_step(tcp_l)
    tcp_l

actor TCPSourceListener is PartitionRoutable
  """
  # TCPSourceListener
  """

  var _notify: TCPSourceListenerNotify
  let _router: Router val
  let _router_registry: RouterRegistry
  let _route_builder: RouteBuilder val
  let _default_in_route_builder: (RouteBuilder val | None)
  var _outgoing_boundaries: Map[String, OutgoingBoundary] val
  let _tcp_sinks: Array[TCPSink] val
  let _default_target: (Step | None)
  var _fd: U32
  var _event: AsioEventID = AsioEvent.none()
  let _limit: USize
  var _count: USize = 0
  var _closed: Bool = false
  var _init_size: USize
  var _max_size: USize
  let _metrics_reporter: MetricsReporter

  new create(source_builder: SourceBuilder val, router: Router val,
    router_registry: RouterRegistry, route_builder: RouteBuilder val,
    outgoing_boundaries: Map[String, OutgoingBoundary] val,
    tcp_sinks: Array[TCPSink] val,
    alfred: Alfred tag,
    auth: AmbientAuth,
    default_target: (Step | None) = None,
    default_in_route_builder: (RouteBuilder val | None) = None,
    target_router: Router val = EmptyRouter,
    host: String = "", service: String = "0", limit: USize = 0,
    init_size: USize = 64, max_size: USize = 16384,
    metrics_reporter: MetricsReporter iso)
  =>
    """
    Listens for both IPv4 and IPv6 connections.
    """
    _notify = SourceListenerNotify(source_builder, alfred, auth, target_router)
    _router = router
    _router_registry = router_registry
    _route_builder = route_builder
    _default_in_route_builder = default_in_route_builder
    _outgoing_boundaries = outgoing_boundaries
    _tcp_sinks = tcp_sinks
    _event = @pony_os_listen_tcp[AsioEventID](this,
      host.cstring(), service.cstring())
    _limit = limit
    _default_target = default_target
    _metrics_reporter = consume metrics_reporter

    _init_size = init_size
    _max_size = max_size
    _fd = @pony_asio_event_fd(_event)
    _notify_listening()
    @printf[I32]((source_builder.name() + " source listening on " + host + ":" + service + "\n").cstring())

  be update_router(router: Router val) =>
    _notify.update_router(router)

  be remove_route_for(moving_step: ConsumerStep) =>
    None

  be add_boundaries(boundaries: Map[String, OutgoingBoundary] val) =>
    let new_boundaries: Map[String, OutgoingBoundary] trn =
      recover Map[String, OutgoingBoundary] end
    // TODO: A persistent map on the field would be much more efficient here
    for (state_name, boundary) in _outgoing_boundaries.pairs() do
      new_boundaries(state_name) = boundary
    end
    for (state_name, boundary) in boundaries.pairs() do
      if not new_boundaries.contains(state_name) then
        new_boundaries(state_name) = boundary
      end
    end
    _outgoing_boundaries = consume new_boundaries

  be _event_notify(event: AsioEventID, flags: U32, arg: U32) =>
    """
    When we are readable, we accept new connections until none remain.
    """
    if event isnt _event then
      return
    end

    if AsioEvent.readable(flags) then
      _accept(arg)
    end

    if AsioEvent.disposable(flags) then
      @pony_asio_event_destroy(_event)
      _event = AsioEvent.none()
    end

  be _conn_closed() =>
    """
    An accepted connection has closed. If we have dropped below the limit, try
    to accept new connections.
    """
    _count = _count - 1

    if _count < _limit then
      _accept()
    end

  fun ref _accept(ns: U32 = 0) =>
    """
    Accept connections as long as we have spawned fewer than our limit.
    """
    if _closed then
      return
    end

    while (_limit == 0) or (_count < _limit) do
      var fd = @pony_os_accept[U32](_event)

      match fd
      | -1 =>
        // Something other than EWOULDBLOCK, try again.
        None
      | 0 =>
        // EWOULDBLOCK, don't try again.
        return
      else
        _spawn(fd)
      end
    end

  fun ref _spawn(ns: U32) =>
    """
    Spawn a new connection.
    """
    try
      let source = TCPSource._accept(this, _notify.connected(this), _router.routes(),
        _route_builder, _outgoing_boundaries, _tcp_sinks, ns, _default_target,
        _default_in_route_builder, _init_size, _max_size,
        _metrics_reporter.clone())
      // TODO: We need to figure out how to unregister this when the
      // connection dies
      _router_registry.register_source(source)
      _count = _count + 1
    else
      @pony_os_socket_close[None](ns)
    end

  fun ref _notify_listening() =>
    """
    Inform the notifier that we're listening.
    """
    if not _event.is_null() then
      _notify.listening(this)
    else
      _closed = true
      _notify.not_listening(this)
    end

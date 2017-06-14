use "buffered"
use "collections"
use "files"
use "serialise"
use "time"
use "sendence/bytes"
use "sendence/rand"
use "wallaroo/boundary"
use "wallaroo/data_channel"
use "wallaroo/fail"
use "wallaroo/initialization"
use "wallaroo/messages"
use "wallaroo/metrics"
use "wallaroo/network"
use "wallaroo/recovery"
use "wallaroo/routing"
use "wallaroo/tcp_sink"
use "wallaroo/tcp_source"
use "wallaroo/topology"

actor WActorInitializer is LayoutInitializer
  let _worker_name: String
  let _app_name: String
  var _system: (LocalActorSystem | None) = None
  let _auth: AmbientAuth
  let _event_log: EventLog
  let _local_actor_system_file: String
  let _input_addrs: Array[Array[String]] val
  let _output_addrs: Array[Array[String]] val
  let _recovery: Recovery
  let _recovery_replayer: RecoveryReplayer
  let _data_channel_file: String
  let _worker_names_file: String
  let _data_receivers: DataReceivers
  let _metrics_conn: MetricsSink
  let _central_registry: CentralWActorRegistry
  var _sinks: Array[TCPSink] val = recover Array[TCPSink] end
  var _outgoing_boundaries: Map[String, OutgoingBoundary] val =
    recover Map[String, OutgoingBoundary] end
  var _outgoing_boundary_builders:
    Map[String, OutgoingBoundaryBuilder val] val =
      recover Map[String, OutgoingBoundaryBuilder val] end
  let _is_initializer: Bool
  let _connections: Connections
  let _router_registry: RouterRegistry

  var _recovered_worker_names: Array[String] val = recover val Array[String] end
  var _recovering: Bool = false


  ////////////////
  // Demo fields
  ////////////////
  let _expected_iterations: USize
  var _iteration: USize = 0
  var _serialized: Array[U8] iso = recover Array[U8] end
  var _received_serialized: USize = 0
  let _actor_count: USize
  let _actors: Array[WActorWrapper tag] = _actors.create()
  let _rand: EnhancedRandom

  new create(worker_name: String, app_name: String,
    auth: AmbientAuth, event_log: EventLog,
    input_addrs: Array[Array[String]] val,
    output_addrs: Array[Array[String]] val, local_actor_system_file: String,
    actor_count: USize, expected_iterations: USize, recovery: Recovery,
    recovery_replayer: RecoveryReplayer,
    data_channel_file: String, worker_names_file: String,
    data_receivers: DataReceivers, metrics_conn: MetricsSink,
    seed: U64, connections: Connections,
    router_registry: RouterRegistry, is_initializer: Bool)
  =>
    _worker_name = worker_name
    _app_name = app_name
    _auth = auth
    _event_log = event_log
    _local_actor_system_file = local_actor_system_file
    _input_addrs = input_addrs
    _output_addrs = output_addrs
    _expected_iterations = expected_iterations
    _actor_count = actor_count
    _recovery = recovery
    _recovery_replayer = recovery_replayer
    _data_channel_file = data_channel_file
    _worker_names_file = worker_names_file
    _data_receivers = data_receivers
    _metrics_conn = metrics_conn
    _rand = EnhancedRandom(seed)
    _connections = connections
    _router_registry = router_registry
    _central_registry = CentralWActorRegistry(_worker_name, _auth, this,
      _connections, _sinks, _event_log, _rand.u64())
    _is_initializer = is_initializer

  be update_actor_to_worker_map(actor_to_worker_map: Map[U128, String] val) =>
    _central_registry.update_actor_to_worker_map(actor_to_worker_map)

  be update_local_actor_system(las: LocalActorSystem) =>
    _system = las
    let sinks: Array[TCPSink] trn = recover Array[TCPSink] end
    try
      for (idx, sink_builder) in las.sinks().pairs() do
        let empty_metrics_reporter =
          MetricsReporter(_app_name, "",
            ReconnectingMetricsSink("", "", "", ""))

        let sink_addr = _output_addrs(idx)
        let host = sink_addr(0)
        let service = sink_addr(1)

        let next_sink = sink_builder(consume empty_metrics_reporter,
          host, service)
        sinks.push(next_sink)
      end
    else
      @printf[I32]("Error creating sinks! Be sure you've provided as many sink addresses as you have defined sinks.\n".cstring())
      Fail()
    end
    _sinks = consume sinks
    _central_registry.update_sinks(_sinks)

  be register_as_role(role: String, id: U128) =>
    match _system
    | let las: LocalActorSystem =>
      _system = las.register_as_role(role, id)
      _save_local_actor_system()
    else
      Fail()
    end

  fun ref _save_worker_names()
  =>
    """
    Save the list of worker names to a file.
    """
    try
      match _system
      | let las: LocalActorSystem val =>
        @printf[I32](("Saving worker names to file: " + _worker_names_file +
          "\n").cstring())
        let worker_names_filepath = FilePath(_auth, _worker_names_file)
        let file = File(worker_names_filepath)
        // Clear file
        file.set_length(0)
        for worker_name in las.worker_names().values() do
          file.print(worker_name)
          @printf[I32](("LocalActorSystem._save_worker_names: " + worker_name +
          "\n").cstring())
        end
        file.sync()
        file.dispose()
      else
        Fail()
      end
    else
      Fail()
    end

  fun ref _save_local_actor_system() =>
    @printf[I32]("||| -- Saving Actor System! -- |||\n".cstring())
    match _system
    | let las: LocalActorSystem =>
      try
        let local_actor_system_file = FilePath(_auth, _local_actor_system_file)
        // TODO: Back up old file before clearing it?
        let file = File(local_actor_system_file)
        // Clear contents of file.
        file.set_length(0)
        let wb = Writer
        let serialised_actor_system: Array[U8] val =
          Serialised(SerialiseAuth(_auth), las).output(
            OutputSerialisedAuth(_auth))
        wb.write(serialised_actor_system)
        file.writev(recover val wb.done() end)
        file.sync()
        file.dispose()
      else
        @printf[I32]("Error saving actor system!\n".cstring())
        Fail()
      end
    else
      @printf[I32]("Error saving actor system!\n".cstring())
      Fail()
    end

  be create_data_channel_listener(ws: Array[String] val,
    host: String, service: String,
    cluster_initializer: (ClusterInitializer | None) = None)
  =>
    match _connections
    | let conns: Connections =>
      try
        let data_channel_filepath = FilePath(_auth, _data_channel_file)
        if not _is_initializer then
          let data_notifier: DataChannelListenNotify iso =
            DataChannelListenNotifier(_worker_name, _auth, conns,
              _is_initializer,
              MetricsReporter(_app_name, _worker_name, _metrics_conn),
              data_channel_filepath, this, _data_receivers, _recovery_replayer,
              _router_registry)

          ifdef "resilience" then
            conns.make_and_register_recoverable_data_channel_listener(
              _auth, consume data_notifier, _router_registry,
              data_channel_filepath, host, service)
          else
            let dch_listener = DataChannelListener(_auth,
              consume data_notifier, _router_registry,
              host, service)
            conns.register_listener(dch_listener)
          end
        else
          match cluster_initializer
            | let ci: ClusterInitializer =>
              conns.create_initializer_data_channel_listener(
                _data_receivers, _recovery_replayer, _router_registry,
                ci, data_channel_filepath, this)
          end
        end
      else
        @printf[I32]("FAIL: cannot create data channel\n".cstring())
      end
    else
      Fail()
    end

  be update_boundaries(bs: Map[String, OutgoingBoundary] val,
    bbs: Map[String, OutgoingBoundaryBuilder val] val)
  =>
    // This should only be called during initialization
    if (_outgoing_boundaries.size() > 0) or
       (_outgoing_boundary_builders.size() > 0)
    then
      Fail()
    end

    _outgoing_boundaries = bs
    _outgoing_boundary_builders = bbs
    _central_registry.update_boundaries(bs)

  be recover_and_initialize(ws: Array[String] val,
    cluster_initializer: (ClusterInitializer | None) = None)
  =>
    match _connections
    | let conns: Connections =>
      _recovering = true
      _recovered_worker_names = ws

      try
        let data_channel_filepath = FilePath(_auth, _data_channel_file)
        if not _is_initializer then
          let data_notifier: DataChannelListenNotify iso =
            DataChannelListenNotifier(_worker_name, _auth, conns,
              _is_initializer,
              MetricsReporter(_app_name, _worker_name, _metrics_conn),
              data_channel_filepath, this, _data_receivers, _recovery_replayer,
              _router_registry)

          ifdef "resilience" then
            conns.make_and_register_recoverable_data_channel_listener(
              _auth, consume data_notifier, _router_registry,
              data_channel_filepath)
          else
            let dch_listener = DataChannelListener(_auth,
              consume data_notifier, _router_registry)
            conns.register_listener(dch_listener)
          end
        else
          match cluster_initializer
          | let ci: ClusterInitializer =>
            conns.create_initializer_data_channel_listener(
              _data_receivers, _recovery_replayer, _router_registry, ci,
              data_channel_filepath, this)
          end
        end
      else
        @printf[I32]("FAIL: cannot create data channel\n".cstring())
      end

      conns.recover_connections(this)
    end

  be initialize(cluster_initializer: (ClusterInitializer | None) = None,
    recovering: Bool = false)
  =>
    try
      ifdef "resilience" then
        let local_actor_system_file = FilePath(_auth, _local_actor_system_file)
        if local_actor_system_file.exists() then
          //we are recovering an existing worker topology
          let data = recover val
            let file = File(local_actor_system_file)
            file.read(file.size())
          end
          match Serialised.input(InputSerialisedAuth(_auth), data)(
            DeserialiseAuth(_auth))
          | let las: LocalActorSystem =>
            _system = las
            @printf[I32]("||| -- Recovered Actor System! -- |||\n".cstring())
          else
            @printf[I32]("error restoring previous actor system!".cstring())
          end
        end
      end

      ifdef "resilience" then
        _save_local_actor_system()
        _save_worker_names()
      end

      match _system
      | let las: LocalActorSystem =>
        match _central_registry
        | let cr: CentralWActorRegistry =>
          las.register_roles_in_registry(cr)

          try
            for (idx, source) in las.sources().pairs() do
              let source_notify = WActorSourceNotify(_auth,
                source._1, source._2, cr, _event_log)

              let source_builder = ActorSystemSourceBuilder(_app_name,
                source._1, source._2, cr)

              let empty_metrics_reporter =
                MetricsReporter(_app_name, "",
                  ReconnectingMetricsSink("", "", "", ""))

              let source_addr = _input_addrs(idx)
              let host = source_addr(0)
              let service = source_addr(1)

              TCPSourceListener(source_builder,
                EmptyRouter, _router_registry, EmptyRouteBuilder,
                _outgoing_boundary_builders, recover Array[TCPSink] end,
                _event_log, _auth, this, consume empty_metrics_reporter
                where host = host, service = service)
            end
          else
            @printf[I32]("Error creating sources! Be sure you've provided as many source addresses as you have defined sources.\n".cstring())
            Fail()
          end

          _central_registry.distribute_data_router(_router_registry)

          _connections.quick_initialize_data_connections(this)

          @printf[I32]("\n#*# Spinning up %lu Wallaroo actors #*#\n\n"
            .cstring(), las.actor_builders().size())
          for builder in las.actor_builders().values() do
            _actors.push(builder(_worker_name, cr, _auth, _event_log,
              las.actor_to_worker_map(), _connections, _outgoing_boundaries,
              _rand.u64()))
          end

          _router_registry.register_boundaries(_outgoing_boundaries,
            _outgoing_boundary_builders)

          if recovering then
            _recovery.start_recovery(this, las.worker_names())
          else
            kick_off_demo()
          end
        else
          Fail()
        end
      else
        Fail()
      end
    else
      Fail()
    end

  be kick_off_demo() =>
    if not _recovering then
      @printf[I32]("\n#########################\n".cstring())
      @printf[I32]("#*# Kicking off demo! #*#\n".cstring())
      @printf[I32]("#########################\n".cstring())
    else
      @printf[I32]("\n###################################\n".cstring())
      @printf[I32]("#*# Recovered: continuing demo! #*#\n".cstring())
      @printf[I32]("###################################\n".cstring())
    end
    let timers = Timers
    let t = Timer(MainNotify(this, _expected_iterations), 1_000_000_000)
    timers(consume t)

  be add_actor(b: WActorWrapperBuilder) =>
    match _system
    | let las: LocalActorSystem =>
      _system = las.add_actor(b, _worker_name)
    end

  be act() =>
    for w_actor in _actors.values() do
      w_actor.process(Act)
      w_actor.pickle(this)
    end
    _iteration = _iteration + 1

  be finish() =>
    for w_actor in _actors.values() do
      w_actor.process(Finish)
    end

  be add_serialized(ser: ByteSeq val) =>
    match ser
    | let s: String =>
      for byte in s.values() do
        _serialized.push(byte)
      end
    | let arr: Array[U8] val =>
      for byte in arr.values() do
        _serialized.push(byte)
      end
    end
    _received_serialized = _received_serialized + 1
    if _received_serialized == _actor_count then
      // TODO: Remove when not needed for DEMO
      // let last = (_serialized = recover Array[U8] end)
      // let digest = Pickle.md5_digest(String.from_iso_array(consume last))
      // @printf[I32]("Digest for iteration %lu: %s\n".cstring(), _iteration,
      //   digest.cstring())
      _received_serialized = 0
      if _iteration < _expected_iterations then
        act()
      else
        finish()
      end
    end

  be receive_immigrant_step(msg: StepMigrationMsg val) =>
    None

class val ActorSystemSourceBuilder is SourceBuilder
  let _app_name: String
  let _handler: WActorFramedSourceHandler
  let _actor_router: WActorRouter
  let _central_actor_registry: CentralWActorRegistry

  new val create(app_name: String, handler: WActorFramedSourceHandler,
    actor_router: WActorRouter, central_actor_registry: CentralWActorRegistry)
  =>
    _app_name = app_name
    _handler = handler
    _actor_router = actor_router
    _central_actor_registry = central_actor_registry

  fun name(): String =>
    _app_name + " source"

  fun apply(event_log: EventLog, auth: AmbientAuth, target_router: Router val):
    TCPSourceNotify iso^
  =>
    WActorSourceNotify(auth, _handler, _actor_router,
      _central_actor_registry, event_log)

  fun val update_router(router: Router val): SourceBuilder =>
    this

class MainNotify is TimerNotify
  let _main: WActorInitializer
  let _n: USize

  new iso create(main: WActorInitializer, n: USize) =>
    _main = main
    _n = n

  fun ref apply(timer: Timer, count: U64): Bool =>
    // If we need to simulate the DCM Toy Model for some
    // reason in future demo runs, we still want this.
    // TODO: Remove this comment and associated code in this file.
    // _main.act()
    false

use "net"
use "collections"
use "buffy/messages"
use "buffy/metrics"
use "sendence/bytes"
use "sendence/tcp"
use "time"
use "spike"

class LeaderControlNotifier is TCPListenNotify
  let _env: Env
  let _auth: AmbientAuth
  let _name: String
  let _topology_manager: TopologyManager
  let _step_manager: StepManager
  let _coordinator: Coordinator
  let _metrics_collector: MetricsCollector
  var _host: String = ""
  var _service: String = ""

  new iso create(env: Env, auth: AmbientAuth, name: String,
    step_manager: StepManager, coordinator: Coordinator,
    topology_manager: TopologyManager, metrics_collector: MetricsCollector) =>
    _env = env
    _auth = auth
    _name = name
    _step_manager = step_manager
    _coordinator = coordinator
    _topology_manager = topology_manager
    _metrics_collector = metrics_collector

  fun ref listening(listen: TCPListener ref) =>
    try
      (_host, _service) = listen.local_address().name()
      _env.out.print(_name + ": listening on " + _host + ":" + _service)
    else
      _env.out.print(_name + ": couldn't get local address")
      listen.close()
    end

  fun ref not_listening(listen: TCPListener ref) =>
    _env.out.print(_name + ": couldn't listen")
    listen.close()

  fun ref connected(listen: TCPListener ref) : TCPConnectionNotify iso^ =>
    LeaderConnectNotify(_env, _auth, _name, _topology_manager,
      _step_manager, _coordinator, _metrics_collector)

class LeaderConnectNotify is TCPConnectionNotify
  let _env: Env
  let _auth: AmbientAuth
  let _name: String
  let _topology_manager: TopologyManager
  let _step_manager: StepManager
  let _coordinator: Coordinator
  let _metrics_collector: MetricsCollector
  let _framer: Framer = Framer
  let _node_internal_conns: Map[String, TCPConnection tag] = Map[String, TCPConnection tag]

  new iso create(env: Env, auth: AmbientAuth, name: String, t_manager: TopologyManager,
    s_manager: StepManager, coordinator: Coordinator,
    metrics_collector: MetricsCollector) =>
    _env = env
    _auth = auth
    _name = name
    _topology_manager = t_manager
    _step_manager = s_manager
    _coordinator = coordinator
    _metrics_collector = metrics_collector

  fun ref accepted(conn: TCPConnection ref) =>
    _coordinator.add_connection(conn)

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso) =>
    for chunked in _framer.chunk(consume data).values() do
      try
        let msg = WireMsgDecoder(consume chunked)
        match msg
        | let m: IdentifyControlMsg val =>
          _topology_manager.assign_control_conn(conn, m.node_name, m.host, m.service)
        | let m: IdentifyInternalMsg val =>
          _topology_manager.assign_internal_conn(conn, m.node_name, m.host, m.service)
        | let m: AckInitializedMsg val =>
          _topology_manager.ack_initialized()
        | let m: ReconnectMsg val =>
          _env.out.print("Received reconnect message, but doing nothing.")
        | let m: SpinUpMsg val =>
          _step_manager.add_step(m.step_id, m.computation_type)
        | let m: SpinUpProxyMsg val =>
          _spin_up_proxy(m)
        | let m: SpinUpSinkMsg val =>
          _step_manager.add_sink(m.sink_id, m.sink_step_id, _auth)
        | let m: ConnectStepsMsg val =>
          _step_manager.connect_steps(m.in_step_id, m.out_step_id)
        | let d: ShutdownMsg val =>
          _topology_manager.shutdown()
        | let m: UnknownMsg val =>
          _env.err.print("Unknown control message type.")
        end
      else
        _env.err.print("Error decoding incoming control message.")
      end
    end

  fun ref _spin_up_proxy(msg: SpinUpProxyMsg val) =>
    try
      let target_conn = _node_internal_conns(msg.target_node_name)
      _step_manager.add_proxy(msg.proxy_id, msg.step_id, target_conn)
    else
      let notifier: TCPConnectionNotify iso =
        LeaderConnectNotify(_env, _auth, _name, _topology_manager, _step_manager,
          _coordinator, _metrics_collector)
      let target_conn =
        TCPConnection(_auth, consume notifier, msg.target_host,
          msg.target_service)
      _step_manager.add_proxy(msg.proxy_id, msg.step_id, target_conn)
      _node_internal_conns(msg.target_node_name) = target_conn
    end

  fun ref closed(conn: TCPConnection ref) =>
    _env.out.print(_name + ": server closed")

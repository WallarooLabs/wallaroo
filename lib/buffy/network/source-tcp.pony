use "net"
use "collections"
use "buffy/messages"
use "buffy/metrics"
use "sendence/messages"
use "sendence/bytes"
use "sendence/guid"
use "sendence/epoch"
use "../topology"
use "random"
use "debug"

class SourceNotifier is TCPListenNotify
  let _env: Env
  let _host: String
  let _service: String
  let _source_id: U64
  let _step_manager: StepManager
  let _coordinator: Coordinator
  let _metrics_collector: MetricsCollector

  new iso create(env: Env, source_host: String,
    source_service: String, source_id: U64, step_manager: StepManager,
    coordinator: Coordinator, metrics_collector: MetricsCollector) =>
    _env = env
    _host = source_host
    _service = source_service
    _source_id = source_id
    _step_manager = step_manager
    _coordinator = coordinator
    _metrics_collector = metrics_collector

  fun ref listening(listen: TCPListener ref) =>
    _env.out.print("Source " + _source_id.string() + ": listening on "
      + _host + ":" + _service)

  fun ref not_listening(listen: TCPListener ref) =>
    _env.out.print("Source " + _source_id.string() + ": couldn't listen")
    listen.close()

  fun ref connected(listen: TCPListener ref) : TCPConnectionNotify iso^ =>
    SourceConnectNotify(_env, _source_id, _step_manager, _coordinator,
      _metrics_collector)

class SourceConnectNotify is TCPConnectionNotify
  let _guid_gen: GuidGenerator = GuidGenerator
  let _env: Env
  let _source_id: U64
  let _step_manager: StepManager
  let _metrics_collector: MetricsCollector
  let _coordinator: Coordinator
  var _header: Bool = true
  var _source_initialized: Bool = false
  var _source_step: BasicOutputStep tag = PassThrough
  var _msg_count: USize = 0

  new iso create(env: Env, source_id: U64,
    step_manager: StepManager, coordinator: Coordinator,
      metrics_collector: MetricsCollector) =>
    _env = env
    _source_id = source_id
    _step_manager = step_manager
    _coordinator = coordinator
    _metrics_collector = metrics_collector

  fun ref accepted(conn: TCPConnection ref) =>
    ifdef debug then
      try
        (let host, _) = conn.remote_address().name()
        Debug.out("SourceConnectNotify.accepted() " + host)
      end
    end

    conn.expect(4)
    _coordinator.add_connection(conn)

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso): Bool =>
    ifdef debug then
      try
        (let host, _) = conn.remote_address().name()
        Debug.out("SourceConnectNotify.received() " + host)
      end
    end

    if _header then
      try
        let expect = Bytes.to_u32(data(0), data(1), data(2), data(3)).usize()
        conn.expect(expect)
        _header = false
      else
        _env.err.print("Error reading header from external source")
      end
    else
      if not _source_initialized then
        _step_manager.passthrough_to_step[String](_source_id, 
          _source_step)
        _source_initialized = true
      end

      let now = Epoch.nanoseconds()
      _source_step.send[String](_guid_gen(), now, now,
        String.from_array(consume data))

      conn.expect(4)
      _header = true
      _msg_count = _msg_count + 1
      if _msg_count >= 5 then
        _msg_count = 0
        return false
      end
    end
    true

  fun ref connected(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": connected.")

  fun ref connect_failed(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": connection failed.")

  fun ref closed(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": server closed")

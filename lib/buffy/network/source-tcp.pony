use "net"
use "collections"
use "buffy/messages"
use "buffy/metrics"
use "sendence/bytes"
use "../topology"
use "time"

class SourceNotifier is TCPListenNotify
  let _env: Env
  let _auth: AmbientAuth
  let _host: String
  let _service: String
  let _source_id: U64
  let _step_manager: StepManager
  let _coordinator: Coordinator
  let _metrics_collector: MetricsCollector

  new iso create(env: Env, auth: AmbientAuth, source_host: String,
    source_service: String, source_id: U64, step_manager: StepManager,
    coordinator: Coordinator, metrics_collector: MetricsCollector) =>
    _env = env
    _auth = auth
    _host = source_host
    _service = source_service
    _source_id = source_id
    _step_manager = step_manager
    _coordinator = coordinator
    _metrics_collector = metrics_collector

  fun ref listening(listen: TCPListener ref) =>
    _env.out.print("Source " + _source_id.string() + ": listening on " + _host + ":" + _service)

  fun ref not_listening(listen: TCPListener ref) =>
    _env.out.print("Source " + _source_id.string() + ": couldn't listen")
    listen.close()

  fun ref connected(listen: TCPListener ref) : TCPConnectionNotify iso^ =>
    SourceConnectNotify(_env, _auth, _source_id, _step_manager, _coordinator,
      _metrics_collector)

class SourceConnectNotify is TCPConnectionNotify
  var _msg_id: U64 = 0
  let _env: Env
  let _auth: AmbientAuth
  let _source_id: U64
  let _step_manager: StepManager
  let _metrics_collector: MetricsCollector
  let _coordinator: Coordinator
  var _header: Bool = true

  new iso create(env: Env, auth: AmbientAuth, source_id: U64,
    step_manager: StepManager, coordinator: Coordinator,
      metrics_collector: MetricsCollector) =>
    _env = env
    _auth = auth
    _source_id = source_id
    _step_manager = step_manager
    _coordinator = coordinator
    _metrics_collector = metrics_collector

  fun ref accepted(conn: TCPConnection ref) =>
    conn.expect(4)
    _coordinator.add_connection(conn)

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso) =>
    if _header then
      try
        let expect = Bytes.to_u32(data(0), data(1), data(2), data(3)).usize()
        conn.expect(expect)
        _header = false
      else
        _env.err.print("Error reading header from external source")
      end
    else
      try
        let msg = ExternalMsgDecoder(consume data)
        match msg
        | let m: ExternalDataMsg val =>
          let now = Time.millis()
          let new_msg: Message[String] val = Message[String](_msg_id = _msg_id + 1,
            now, now, m.data)
          _step_manager(_source_id, new_msg)
        | let m: ExternalUnknownMsg val =>
          _env.err.print("Unknown message type.")
        else
          _env.err.print("Source " + _source_id.string()
            + ": decoded message wasn't external.")
        end
      else
        _env.err.print("Error decoding incoming message.")
      end

      conn.expect(4)
      _header = true
    end

  fun ref connected(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": connected.")

  fun ref connect_failed(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": connection failed.")

  fun ref closed(conn: TCPConnection ref) =>
    _env.out.print("Source " + _source_id.string() + ": server closed")

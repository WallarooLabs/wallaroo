use "net"
use "collections"
use "buffy/messages"
use "sendence/bytes"
use "sendence/epoch"
use "buffy/topology"

class SinkNodeNotifier is TCPListenNotify
  let _env: Env
  let _auth: AmbientAuth
  let _sink_node_step: StringInStep tag
  let _host: String
  let _service: String

  new iso create(env: Env, auth: AmbientAuth, sink_node_step: StringInStep tag, 
    host: String, service: String) =>
    _env = env
    _auth = auth
    _sink_node_step = sink_node_step
    _host = host
    _service = service

  fun ref listening(listen: TCPListener ref) =>
    _env.out.print("Sink node: listening on " + _host + ":" + _service)

  fun ref not_listening(listen: TCPListener ref) =>
    _env.out.print("Sink node: couldn't listen")
    listen.close()

  fun ref connected(listen: TCPListener ref) : TCPConnectionNotify iso^ =>
    SinkNodeConnectNotify(_env, _auth, _sink_node_step)

class SinkNodeConnectNotify is TCPConnectionNotify
  let _env: Env
  let _auth: AmbientAuth
  let _sink_node_step: StringInStep tag
  var _header: Bool = true

  new iso create(env: Env, auth: AmbientAuth, sink_node_step: StringInStep tag) =>
    _env = env
    _auth = auth
    _sink_node_step = sink_node_step

  fun ref accepted(conn: TCPConnection ref) =>
    conn.expect(4)

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
        let decoded = ExternalMsgDecoder(consume data)
        match decoded
        | let d: ExternalDataMsg val =>
          _sink_node_step(d.data)
        else
          _env.err.print("sink node: Unexpected data")
        end
      else
        _env.err.print("sink node: Unable to decode message")
      end

      conn.expect(4)
      _header = true
    end

  fun ref connected(conn: TCPConnection ref) =>
    _env.out.print("Sink node: connected.")

  fun ref connect_failed(conn: TCPConnection ref) =>
    _env.out.print("Sink node: connection failed.")

  fun ref closed(conn: TCPConnection ref) =>
    _env.out.print("Sink node: server closed")


class SinkNodeOutConnectNotify is TCPConnectionNotify
  let _env: Env

  new iso create(env: Env) =>
    _env = env

  fun ref accepted(conn: TCPConnection ref) =>
    _env.out.print("sink out: sink connection accepted")

  fun ref received(conn: TCPConnection ref, data: Array[U8] iso) =>
    _env.out.print("sink out: received")

  fun ref closed(conn: TCPConnection ref) =>
    _env.out.print("sink out: server closed")


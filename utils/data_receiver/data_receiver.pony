/*

Copyright 2017 The Wallaroo Authors.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 implied. See the License for the specific language governing
 permissions and limitations under the License.

*/

use "net"
use "wallaroo_labs/bytes"
use "wallaroo_labs/logging"
use "wallaroo_labs/options"

actor Main
  new create(env: Env) =>
    var required_args_are_present = true
    var l_arg: (Array[String] | None) = None
    var output_mode: OutputMode = Write
    var input_mode: InputMode = Streaming

    let sev_emergency = U8(0)
    let sev_alert = U8(1)
    let sev_crit = U8(2)
    let sev_error = U8(3)
    let cat_mumble = U8(40)

    @printf[I32]("SLF: Hello, world!\n".cstring()) // For demo purposes only
    @l[I32](sev_crit, cat_mumble, "SLF: Hello, %s!\n".cstring(), "everything".cstring()) // For demo purposes only
    @w_set_severity[None](sev_crit, "2-severity-yo".cstring())
    @w_set_category[None](cat_mumble, "my-mumble-cat".cstring())
    @l[I32](sev_crit, cat_mumble, "SLF: Hello, %s!\n".cstring(), "everything".cstring()) // For demo purposes only

    @w_severity_threshold[None](sev_alert)
    @l[I32](sev_emergency, cat_mumble, "SLF: visible!\n".cstring()) // For demo purposes only
    @l[I32](sev_alert, cat_mumble, "SLF: visible!\n".cstring()) // For demo purposes only
    @l[I32](sev_crit, cat_mumble, "SLF: this one should be filtered out\n".cstring()) // For demo purposes only

    @printf[I32]("SLF: emergency enabled = 1? res = %s\n".cstring(),
      @le[Bool](sev_emergency, cat_mumble).string().cstring())
    @printf[I32]("SLF: alert enabled = 1? res = %s\n".cstring(),
      @le[Bool](sev_alert, cat_mumble).string().cstring())
    @printf[I32]("SLF: critical enabled = 0? res = %s\n".cstring(),
      @le[Bool](sev_crit, cat_mumble).string().cstring())

    try
      var options = Options(env.args)

      options.add("framed", "f", None)
      options.add("help", "h", None)
      options.add("listen", "l", StringArgument)
      options.add("no-write", "n", None)

      for option in options do
        match option
        | ("help", None) => usage(env.out); return
        | ("listen", let arg: String) => l_arg = arg.split(":")
        | ("no-write", None) => output_mode = NoWrite
        | ("framed", None) => input_mode = Framed
        | let err: ParseError =>
          err.report(env.err)
          usage(env.out)
        end
      end

      if l_arg is None then
        env.err.print("Must supply required '--listen' argument")
        required_args_are_present = false
      else
        if (l_arg as Array[String]).size() != 2 then
          env.err.print(
            "'--listen' argument should be in format: '127.0.0.1:7669")
          required_args_are_present = false
        end
      end

      if not required_args_are_present then
        error
      end

      // Start it up!
      let listener_addr = l_arg as Array[String]
      let host = listener_addr(0)?
      let port = listener_addr(1)?
      let tcp_auth = TCPListenAuth(env.root as AmbientAuth)
      TCPListener(tcp_auth,
        ListenerNotify(env.out, env.err, input_mode, output_mode, host, port),
        host, port)
    else
      usage(env.out)
    end

  fun usage(out: OutStream) =>
    out.print(
      "data_receiver [OPTIONS]\n" +
      "Required: \n" +
      "  --listen   ADDRESS:PORT  e.g. 127.0.0.1:7669\n" +
      "    Address and port to listen for data on.\n" +
      "Optional: \n" +
      "  --no-write\n" +
      "    Don't write received data to STDOUT\n" +
      "  --framed\n" +
      "    Read a framed message protocol with 4 byte header\n"
      )

class ListenerNotify is TCPListenNotify
  let _stdout: OutStream
  let _stderr: OutStream
  let _input_mode: InputMode
  let _output_mode: OutputMode
  let _host: String
  let _port: String

  new iso create(stdout: OutStream,
    stderr: OutStream,
    input_mode: InputMode,
    output_mode: OutputMode,
    host: String,
    port: String)
  =>
    _stdout = stdout
    _stderr = stderr
    _input_mode = input_mode
    _output_mode = output_mode
    _host = host
    _port = port

  fun ref listening(listen: TCPListener ref) =>
    _stdout.print("Listening on " + _host + ":" + _port)

  fun ref not_listening(listen: TCPListener ref) =>
    _stderr.print("Unable to listen\n")

  fun ref connected(listen: TCPListener ref): TCPConnectionNotify iso^ =>
    ConnectionNotify(_stdout, _stderr, _input_mode, _output_mode)

class ConnectionNotify is TCPConnectionNotify
  let _stdout: OutStream
  let _stderr: OutStream
  let _input_mode: InputMode
  let _output_mode: OutputMode
  var _read_header: Bool = true

  new iso create(so: OutStream, se: OutStream, i: InputMode, o: OutputMode) =>
    _stdout = so
    _stderr = se
    _input_mode = i
    _output_mode = o

  fun ref received(c: TCPConnection ref, d: Array[U8] iso, n: USize): Bool =>
    match _input_mode
    | Framed =>
      if _read_header then
        try
          let expect = Bytes.to_u32(d(0)?, d(1)?, d(2)?, d(3)?).usize()
          c.expect(expect)
          _read_header = false
        else
          _stderr.print("Bad framed header value. Exiting.")
          c.close()
        end
      else
        match _output_mode
        | Write =>
          _stdout.print(consume d)
        end
        c.expect(4)
        _read_header = true
      end
    | Streaming =>
      match _output_mode
      | Write => _stdout.write(consume d)
      end
    end

    true

  fun ref accepted(c: TCPConnection ref) =>
    match _input_mode
    | Framed => c.expect(4)
    end

  fun ref connect_failed(c: TCPConnection ref) =>
    // We don't initiate outgoing connections so this can never happen
    None

primitive Write
primitive NoWrite

type OutputMode is (Write | NoWrite)

primitive Streaming
primitive Framed

type InputMode is (Streaming | Framed)

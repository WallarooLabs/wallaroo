use "buffered"
use "collections"
use "net"
use "wallaroo_labs/bytes"

use @pony_asio_event_create[AsioEventID](owner: AsioEventNotify, fd: U32,
  flags: U32, nsec: U64, noisy: Bool)
use @pony_asio_event_fd[U32](event: AsioEventID)
use @pony_asio_event_unsubscribe[None](event: AsioEventID)
use @pony_asio_event_resubscribe_read[None](event: AsioEventID)
use @pony_asio_event_resubscribe_write[None](event: AsioEventID)
use @pony_asio_event_destroy[None](event: AsioEventID)


trait TCPActor
  // This behavior must be implemented so that the Pony runtime can
  // call it.
  be _event_notify(event: AsioEventID, flags: U32, arg: U32)
  be write_again()
  be read_again()
  fun ref expect(qty: USize = 0)
  fun ref set_nodelay(state: Bool)
  fun ref close()

trait TestableTCPHandler[T: TCPActor ref]
  fun is_connected(): Bool

  fun ref connect(host: String, service: String, from: String,
    conn: TCPActor ref)

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32,
    actor_type: T)

  fun ref writev(data: ByteSeqIter)

  fun ref close()

  fun can_send(): Bool

  fun ref read_again()

  fun ref write_again()

  fun ref expect(qty: USize)

  fun ref set_nodelay(state: Bool)

class EmptyTCPHandler[T: TCPActor ref] is TestableTCPHandler[T]
  fun is_connected(): Bool => false

  fun ref connect(host: String, service: String, from: String,
    conn: TCPActor ref)
  =>
    None

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32,
    actor_type: T)
  =>
    None

  fun ref writev(data: ByteSeqIter) =>
    None

  fun ref close() =>
    None

  fun can_send(): Bool =>
    false

  fun ref read_again() =>
    None

  fun ref write_again() =>
    None

  fun ref expect(qty: USize) =>
    None

  fun ref set_nodelay(state: Bool) =>
    None

class TCPHandler[T: TCPActor ref] is TestableTCPHandler[T]
  let _tcp_actor: T
  let _notify: TCPHandlerNotify[T]
  var _read_buf: Array[U8] iso
  var _next_size: USize
  let _max_size: USize
  var _connect_count: U32 = 0
  var _fd: U32 = -1
  var _in_sent: Bool = false
  var _expect: USize = 0
  var _connected: Bool = false
  var _closed: Bool = false
  var _writeable: Bool = false
  var _throttled: Bool = false
  var _event: AsioEventID = AsioEvent.none()
  embed _pending: List[(ByteSeq, USize)] = _pending.create()
  embed _pending_writev: Array[USize] = _pending_writev.create()
  var _pending_writev_total: USize = 0
  var _shutdown_peer: Bool = false
  var _readable: Bool = false
  var _read_len: USize = 0
  var _shutdown: Bool = false
  var _muted: Bool = false
  var _expect_read_buf: Reader = Reader

  new create(tcp_actor: T, notify: TCPHandlerNotify[T],
    init_size: USize, max_size: USize)
  =>
    _tcp_actor = tcp_actor
    _notify = notify
    _read_buf = recover Array[U8].>undefined(init_size) end
    _next_size = init_size
    _max_size = max_size

  fun is_connected(): Bool =>
    _connected

  fun ref connect(host: String, service: String, from: String,
    conn: TCPActor ref)
  =>
    if not _connected then
      _connect_count = @pony_os_connect_tcp[U32](conn,
        host.cstring(), service.cstring(), from.cstring())
      _notify_connecting()
    end

  fun ref event_notify(event: AsioEventID, flags: U32, arg: U32,
    actor_type: T)
  =>
    """
    Handle socket events.
    """
    if event isnt _event then
      if AsioEvent.writeable(flags) then
        // A connection has completed.
        var fd = @pony_asio_event_fd(event)
        _connect_count = _connect_count - 1

        if not _connected and not _closed then
          // We don't have a connection yet.
          if @pony_os_connected[Bool](fd) then
            // The connection was successful, make it ours.
            _fd = fd
            _event = event
            _connected = true
            _writeable = true
            _readable = true

            _notify.connected(_tcp_actor)
            _pending_reads()

            ifdef not windows then
              if _pending_writes() then
                //sent all data; release backpressure
                _release_backpressure()
              end
            end
          else
            // The connection failed, unsubscribe the event and close.
            @pony_asio_event_unsubscribe(event)
            @pony_os_socket_close[None](fd)
            _notify_connecting()
          end
        elseif not _connected and _closed then
          @printf[I32]("Reconnection asio event\n".cstring())
          if @pony_os_connected[Bool](fd) then
            // The connection was successful, make it ours.
            _fd = fd
            _event = event

            // clear anything pending to be sent because on recovery we're
            // going to have to replay from our queue when requested
            _pending_writev.clear()
            _pending.clear()
            _pending_writev_total = 0

            _connected = true
            _writeable = true
            _readable = true

            _closed = false
            _shutdown = false
            _shutdown_peer = false

            _notify.connected(_tcp_actor)
            _pending_reads()

            ifdef not windows then
              if _pending_writes() then
                //sent all data; release backpressure
                _release_backpressure()
              end
            end
          else
            // The connection failed, unsubscribe the event and close.
            @pony_asio_event_unsubscribe(event)
            @pony_os_socket_close[None](fd)
            _notify_connecting()
          end
        else
          // We're already connected, unsubscribe the event and close.
          @pony_asio_event_unsubscribe(event)
          @pony_os_socket_close[None](fd)
        end
      else
        // It's not our event.
        if AsioEvent.disposable(flags) then
          // It's disposable, so dispose of it.
          @pony_asio_event_destroy(event)
        end
      end
    else
      // At this point, it's our event.
      if _connected and not _shutdown_peer then
        if AsioEvent.writeable(flags) then
          _writeable = true
          ifdef not windows then
            if _pending_writes() then
              //sent all data; release backpressure
              _release_backpressure()
            end
          end
        end

        if AsioEvent.readable(flags) then
          _readable = true
          _pending_reads()
        end
      end

      if AsioEvent.disposable(flags) then
        @pony_asio_event_destroy(event)
        _event = AsioEvent.none()
      end

      _try_shutdown(where locally_initiated_close = false)
    end

  fun ref writev(data: ByteSeqIter) =>
    """
    Write a sequence of sequences of bytes.
    """
    _in_sent = true

    var data_size: USize = 0
    for bytes in _notify.sentv(_tcp_actor, data).values() do
      _pending_writev.>push(bytes.cpointer().usize()).>push(bytes.size())
      _pending_writev_total = _pending_writev_total + bytes.size()
      _pending.push((bytes, 0))
      data_size = data_size + bytes.size()
    end

    _pending_writes()

    _in_sent = false

  fun ref _write_final(data: ByteSeq) =>
    """
    Write as much as possible to the socket. Set _writeable to false if not
    everything was written. On an error, close the connection. This is for
    data that has already been transformed by the notifier.
    """
    _pending_writev.>push(data.cpointer().usize()).>push(data.size())
    _pending_writev_total = _pending_writev_total + data.size()

    _pending.push((data, 0))
    _pending_writes()

  fun ref _notify_connecting() =>
    """
    Inform the notifier that we're connecting.
    """
    if _connect_count > 0 then
      _notify.connecting(_tcp_actor, _connect_count)
    else
      _notify.connect_failed(_tcp_actor)
      _hard_close()
    end

  fun ref close() =>
    """
    Perform a graceful shutdown. Don't accept new writes, but don't finish
    closing until we get a zero length read.
    """
    _closed = true
    _try_shutdown(where locally_initiated_close = true)

  fun ref _try_shutdown(locally_initiated_close: Bool) =>
    """
    If we have closed and we have no remaining writes or pending connections,
    then shutdown.
    """
    if not _closed then
      return
    end

    if
      not _shutdown and
      (_connect_count == 0) and
      (_pending_writev_total == 0)
    then
      _shutdown = true

      if _connected then
        @pony_os_socket_shutdown[None](_fd)
      else
        _shutdown_peer = true
      end
    end

    if _connected and _shutdown and _shutdown_peer then
      _hard_close(locally_initiated_close)
    end

  fun ref _hard_close(locally_initiated_close: Bool = false) =>
    """
    When an error happens, do a non-graceful close.
    """
    if not _connected then
      return
    end

    _connected = false
    _closed = true
    _shutdown = true
    _shutdown_peer = true

    // Unsubscribe immediately and drop all pending writes.
    @pony_asio_event_unsubscribe(_event)
    _pending_writev.clear()
    _pending.clear()
    _pending_writev_total = 0
    _readable = false
    _writeable = false
    @pony_asio_event_set_readable[None](_event, false)
    @pony_asio_event_set_writeable[None](_event, false)

    @pony_os_socket_close[None](_fd)
    _fd = -1

    _notify.closed(_tcp_actor, locally_initiated_close)

  fun ref _pending_reads() =>
    """
    Unless this connection is currently muted, read while data is available,
    guessing the next packet length as we go. If we read 4 kb of data, send
    ourself a resume message and stop reading, to avoid starving other actors.
    """
    try
      var sum: USize = 0
      var received_called: USize = 0

      while _readable and not _shutdown_peer do
        if _muted then
          return
        end

        // Read as much data as possible.
        let len = @pony_os_recv[USize](
          _event,
          _read_buf.cpointer().usize() + _read_len,
          _read_buf.size() - _read_len) ?

        match len
        | 0 =>
          // Would block, try again later.
          // this is safe because asio thread isn't currently subscribed
          // for a read event so will not be writing to the readable flag
          @pony_asio_event_set_readable[None](_event, false)
          _readable = false
          @pony_asio_event_resubscribe_read(_event)
          return
        | _next_size =>
          // Increase the read buffer size.
          _next_size = _max_size.min(_next_size * 2)
        end

        _read_len = _read_len + len

        if _read_len >= _expect then
          let data = _read_buf = recover Array[U8] end
          data.truncate(_read_len)
          _read_len = 0

          received_called = received_called + 1
          if not _notify.received(_tcp_actor, consume data,
            received_called)
          then
            _read_buf_size()
            _tcp_actor.read_again()
            return
          else
            _read_buf_size()
          end

          sum = sum + len

          if sum >= _max_size then
            // If we've read _max_size, yield and read again later.
            _tcp_actor.read_again()
            return
          end
        end
      end
    else
      // The socket has been closed from the other side.
      _shutdown_peer = true
      _hard_close()
    end

  fun can_send(): Bool =>
    _connected and
      _writeable and
      not _closed

  fun ref read_again() =>
    """
    Resume reading.
    """
    _pending_reads()

  fun ref write_again() =>
    """
    Resume writing.
    """
    _pending_writes()

  fun ref _pending_writes(): Bool =>
    """
    Send pending data. If any data can't be sent, keep it and mark as not
    writeable. On an error, dispose of the connection. Returns whether
    it sent all pending data or not.
    """
    // TODO: Make writev_batch_size user configurable
    let writev_batch_size: USize = @pony_os_writev_max[I32]().usize()
    var num_to_send: USize = 0
    var bytes_to_send: USize = 0
    var bytes_sent: USize = 0
    while _writeable and not _shutdown_peer and (_pending_writev_total > 0) do
      // yield if we sent max bytes
      if bytes_sent > _max_size then
        _tcp_actor.write_again()
        return false
      end
      try
        //determine number of bytes and buffers to send
        if (_pending_writev.size()/2) < writev_batch_size then
          num_to_send = _pending_writev.size()/2
          bytes_to_send = _pending_writev_total
        else
          //have more buffers than a single writev can handle
          //iterate over buffers being sent to add up total
          num_to_send = writev_batch_size
          bytes_to_send = 0
          for d in Range[USize](1, num_to_send*2, 2) do
            bytes_to_send = bytes_to_send + _pending_writev(d)?
          end
        end

        // Write as much data as possible.
        var len = @pony_os_writev[USize](_event,
          _pending_writev.cpointer(), num_to_send) ?

        // keep track of how many bytes we sent
        bytes_sent = bytes_sent + len

        if len < bytes_to_send then
          while len > 0 do
            let iov_p = _pending_writev(0)?
            let iov_s = _pending_writev(1)?
            if iov_s <= len then
              len = len - iov_s
              _pending_writev.shift()?
              _pending_writev.shift()?
              _pending.shift()?
              _pending_writev_total = _pending_writev_total - iov_s
            else
              _pending_writev.update(0, iov_p+len)?
              _pending_writev.update(1, iov_s-len)?
              _pending_writev_total = _pending_writev_total - len
              len = 0
            end
          end
          _apply_backpressure()
        else
          // sent all data we requested in this batch
          _pending_writev_total = _pending_writev_total - bytes_to_send
          if _pending_writev_total == 0 then
            _pending_writev.clear()
            _pending.clear()

            return true
          else
            for d in Range[USize](0, num_to_send, 1) do
              _pending_writev.shift()?
              _pending_writev.shift()?
              _pending.shift()?
            end
          end
        end
      else
        // Non-graceful shutdown on error.
        _hard_close()
      end
    end

    false

  fun ref _read_buf_size() =>
    """
    Resize the read buffer.
    """
    if _expect != 0 then
      _read_buf.undefined(_expect)
    else
      _read_buf.undefined(_next_size)
    end

  fun ref expect(qty: USize = 0) =>
    """
    A `received` call on the notifier must contain exactly `qty` bytes. If
    `qty` is zero, the call can contain any amount of data. This has no effect
    if called in the `sent` notifier callback.
    """
    if not _in_sent then
      _expect = _notify.expect(_tcp_actor, qty)
      _read_buf_size()
    end

  fun ref set_nodelay(state: Bool) =>
    """
    Turn Nagle on/off. Defaults to on. This can only be set on a connected
    socket.
    """
    if _connected then
      @pony_os_nodelay[None](_fd, state)
    end

  fun ref _apply_backpressure() =>
    if not _throttled then
      _throttled = true
      _notify.throttled(_tcp_actor)
    end
    _writeable = false
    // this is safe because asio thread isn't currently subscribed
    // for a write event so will not be writing to the readable flag
    @pony_asio_event_set_writeable[None](_event, false)
    @pony_asio_event_resubscribe_write(_event)

  fun ref _release_backpressure() =>
    if _throttled then
      _throttled = false
      _notify.unthrottled(_tcp_actor)
    end

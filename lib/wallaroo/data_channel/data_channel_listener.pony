/*

Copyright (C) 2016-2017, Sendence LLC
Copyright (C) 2016-2017, The Pony Developers
Copyright (c) 2014-2015, Causality Ltd.
All rights reserved.

Redistribution and use in source and binary forms, with or without
modification, are permitted provided that the following conditions are met:

1. Redistributions of source code must retain the above copyright notice, this
   list of conditions and the following disclaimer.
2. Redistributions in binary form must reproduce the above copyright notice,
   this list of conditions and the following disclaimer in the documentation
   and/or other materials provided with the distribution.

THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT OWNER OR CONTRIBUTORS BE LIABLE FOR
ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
(INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
(INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.

*/

use "collections"
use "net"
use "wallaroo/boundary"
use "wallaroo/ent/data_receiver"
use "wallaroo/ent/router_registry"
use "wallaroo/topology"

type DataChannelListenerAuth is (AmbientAuth | NetAuth | TCPAuth |
  TCPListenAuth)

actor DataChannelListener
  var _notify: DataChannelListenNotify
  var _fd: U32
  var _event: AsioEventID = AsioEvent.none()
  var _closed: Bool = false
  let _limit: USize
  var _count: USize = 0
  var _paused: Bool = false
  var _init_size: USize
  var _max_size: USize

  let _router_registry: RouterRegistry

  new create(auth: DataChannelListenerAuth,
    notify: DataChannelListenNotify iso,
    router_registry: RouterRegistry,
    host: String = "", service: String = "0", limit: USize = 0,
    init_size: USize = 64, max_size: USize = 16384)
  =>
    """
    Listens for both IPv4 and IPv6 connections.
    """
    _router_registry = router_registry
    _limit = limit
    _notify = consume notify
    _event = @pony_os_listen_tcp[AsioEventID](this,
      host.cstring(), service.cstring())
    _init_size = init_size
    _max_size = max_size
    _fd = @pony_asio_event_fd(_event)
    _notify_listening()

  be set_notify(notify: DataChannelListenNotify iso) =>
    """
    Change the notifier.
    """
    _notify = consume notify

  be dispose() =>
    """
    Stop listening.
    """
    close()

  fun local_address(): IPAddress =>
    """
    Return the bound IP address.
    """
    let ip = recover IPAddress end
    @pony_os_sockname[Bool](_fd, ip)
    ip

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

    if _paused and (_count < _limit) then
      _paused = false
      _accept()
    end

  fun ref _accept(ns: U32 = 0) =>
    """
    Accept connections as long as we have spawned fewer than our limit.
    """
    ifdef windows then
      if ns == -1 then
        // Unsubscribe when we get an invalid socket in the event.
        @pony_asio_event_unsubscribe(_event)
        return
      end

      if ns > 0 then
        if _closed then
          @pony_os_socket_close[None](ns)
          return
        end

        _spawn(ns)
      end

      // Queue an accept if we're not at the limit.
      if (_limit == 0) or (_count < _limit) then
        @pony_os_accept[U32](_event)
      else
        _paused = true
      end
    else
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

      _paused = true
    end

  fun ref _spawn(ns: U32) =>
    """
    Spawn a new connection.
    """
    try
      let data_channel = DataChannel._accept(this, _notify.connected(this,
        _router_registry), ns, _init_size, _max_size)
      _router_registry.register_data_channel(data_channel)
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

  fun ref close() =>
    """
    Dispose of resources.
    """
    if _closed then
      return
    end

    _closed = true

    if not _event.is_null() then
      @pony_os_socket_close[None](_fd)
      _fd = -1

      // When not on windows, the unsubscribe is done immediately.
      ifdef not windows then
        @pony_asio_event_unsubscribe(_event)
      end

      _notify.closed(this)
    end

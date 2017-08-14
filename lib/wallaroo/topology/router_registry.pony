use "collections"
use "net"
use "time"
use "wallaroo/boundary"
use "wallaroo/data_channel"
use "wallaroo/core"
use "wallaroo/fail"
use "wallaroo/network"
use "wallaroo/recovery"
use "wallaroo/routing"
use "wallaroo/source"
use "wallaroo/w_actor"

actor RouterRegistry
  let _auth: AmbientAuth
  let _data_receivers: DataReceivers
  let _worker_name: String
  let _connections: Connections
  var _data_router: DataRouter =
    DataRouter(recover Map[U128, Consumer] end)
  var _pre_state_data: (Array[PreStateData] val | None) = None
  let _partition_routers: Map[String, PartitionRouter] =
    _partition_routers.create()
  var _omni_router: (OmniRouter | None) = None
  var _actor_data_router: ActorSystemDataRouter = EmptyActorSystemDataRouter

  var _application_ready_to_work: Bool = false

  let _sources: SetIs[Source] = _sources.create()
  let _source_listeners: SetIs[SourceListener] = _source_listeners.create()
  let _data_channel_listeners: SetIs[DataChannelListener] =
    _data_channel_listeners.create()
  let _control_channel_listeners: SetIs[TCPListener] =
    _control_channel_listeners.create()
  let _data_channels: SetIs[DataChannel] = _data_channels.create()
  // All steps that have a PartitionRouter
  let _partition_router_steps: SetIs[Step] = _partition_router_steps.create()
  // All steps that have an OmniRouter
  let _omni_router_steps: SetIs[Step] = _omni_router_steps.create()
  // Boundary builders are used by new TCPSources to create their own
  // individual boundaries to other workers (to allow for increased
  // throughput).
  let _outgoing_boundaries_builders: Map[String, OutgoingBoundaryBuilder] =
    _outgoing_boundaries_builders.create()
  let _outgoing_boundaries: Map[String, OutgoingBoundary] =
    _outgoing_boundaries.create()

  //////
  // Partition Migration
  //////
  var _migrating: Bool = false
  // Steps migrated out and waiting for acknowledgement
  let _step_waiting_list: SetIs[U128] = _step_waiting_list.create()
  // Workers in running cluster that have been stopped for migration
  let _stopped_worker_waiting_list: _StringSet =
    _stopped_worker_waiting_list.create()
  // Migration targets that have not yet acked migration batch complete
  let _migration_target_ack_list: _StringSet =
    _migration_target_ack_list.create()
  // Used as a proxy for RouterRegistry when muting and unmuting sources
  // and data channel.
  // TODO: Probably change mute()/unmute() interface so we don't need this
  let _dummy_consumer: DummyConsumer = DummyConsumer

  var _stop_the_world_pause: U64

  var _waiting_to_finish_join: Bool = false

  new create(auth: AmbientAuth, worker_name: String,
    data_receivers: DataReceivers, c: Connections, stop_the_world_pause: U64)
  =>
    _auth = auth
    _worker_name = worker_name
    _data_receivers = data_receivers
    _connections = c
    _stop_the_world_pause = stop_the_world_pause

  fun _worker_count(): USize =>
    _outgoing_boundaries.size() + 1

  be application_ready_to_work() =>
    _application_ready_to_work = true

  be set_data_router(dr: DataRouter) =>
    _data_router = dr
    _actor_data_router = dr.actor_system_data_router()
    _distribute_data_router()

  be set_pre_state_data(psd: Array[PreStateData] val) =>
    _pre_state_data = psd

  be set_partition_router(state_name: String, pr: PartitionRouter) =>
    _partition_routers(state_name) = pr

  be set_omni_router(o: OmniRouter) =>
    _omni_router = o

  be update_actor_data_router(adr: ActorSystemDataRouter) =>
    _actor_data_router = adr

  be register_source(tcp_source: Source) =>
    _sources.set(tcp_source)
    if not _migrating and _application_ready_to_work then
      tcp_source.unmute(_dummy_consumer)
    end

  be register_source_listener(tcp_source_listener: SourceListener) =>
    _source_listeners.set(tcp_source_listener)

  be register_data_channel_listener(dchl: DataChannelListener) =>
    _data_channel_listeners.set(dchl)
    if _waiting_to_finish_join and
      (_control_channel_listeners.size() != 0)
    then
      _inform_cluster_of_join()
      _waiting_to_finish_join = false
    end

  be register_control_channel_listener(cchl: TCPListener) =>
    _control_channel_listeners.set(cchl)
    if _waiting_to_finish_join and
      (_data_channel_listeners.size() != 0)
    then
      _inform_cluster_of_join()
      _waiting_to_finish_join = false
    end

  be register_data_channel(dc: DataChannel) =>
    // TODO: These need to be unregistered if they close
    _data_channels.set(dc)

  be register_partition_router_step(s: Step) =>
    _partition_router_steps.set(s)

  be register_omni_router_step(s: Step) =>
    _omni_router_steps.set(s)

  be register_boundaries(bs: Map[String, OutgoingBoundary] val,
    bbs: Map[String, OutgoingBoundaryBuilder] val)
  =>
    // Boundaries
    let new_boundaries: Map[String, OutgoingBoundary] trn =
      recover Map[String, OutgoingBoundary] end
    for (worker, boundary) in bs.pairs() do
      if not _outgoing_boundaries.contains(worker) then
        _outgoing_boundaries(worker) = boundary
        new_boundaries(worker) = boundary
      end
    end
    let new_boundaries_sendable: Map[String, OutgoingBoundary] val =
      consume new_boundaries

    for step in _partition_router_steps.values() do
      step.add_boundaries(new_boundaries_sendable)
    end
    for step in _omni_router_steps.values() do
      step.add_boundaries(new_boundaries_sendable)
    end
    for step in _data_router.routes().values() do
      match step
      | let s: Step => s.add_boundaries(new_boundaries_sendable)
      end
    end

    // Boundary builders
    let new_boundary_builders: Map[String, OutgoingBoundaryBuilder] trn =
      recover Map[String, OutgoingBoundaryBuilder] end
    for (worker, builder) in bbs.pairs() do
      // Boundary builders should always be registered after the canonical
      // boundary for each builder. The canonical is used on all Steps.
      // Sources use the builders to create a new boundary per source
      // connection.
      if not _outgoing_boundaries.contains(worker) then
        Fail()
      end
      if not _outgoing_boundaries_builders.contains(worker) then
        new_boundary_builders(worker) = builder
      end
    end

    let new_boundary_builders_sendable:
      Map[String, OutgoingBoundaryBuilder] val =
        consume new_boundary_builders

    for source_listener in _source_listeners.values() do
      source_listener.add_boundary_builders(new_boundary_builders_sendable)
    end

    for source in _sources.values() do
      source.add_boundary_builders(new_boundary_builders_sendable)
    end

  be register_actor_for_worker(id: U128, worker: String) =>
    _actor_data_router.register_actor_for_worker(id, worker)

  be register_as_role(role: String, w_actor: U128) =>
    _actor_data_router.register_as_role(role, w_actor)

  be forget_external_actor(id: U128) =>
    _actor_data_router.forget_external_actor(id)

  be broadcast_to_actors(data: Any val) =>
    _actor_data_router.broadcast_to_actors(data)

  be process_digest(digest: WActorRegistryDigest) =>
    _actor_data_router.process_digest(digest)

  be send_digest_to(worker: String) =>
    _actor_data_router.send_digest_to(worker)

  fun _distribute_data_router() =>
    _data_receivers.update_data_router(_data_router)

  fun _distribute_partition_router(partition_router: PartitionRouter) =>
      for step in _partition_router_steps.values() do
        step.update_router(partition_router)
      end
      for source in _sources.values() do
        source.update_router(partition_router)
      end
      for source_listener in _source_listeners.values() do
        source_listener.update_router(partition_router)
      end

  be inform_cluster_of_join() =>
    _inform_cluster_of_join()

  fun ref _inform_cluster_of_join() =>
    if (_data_channel_listeners.size() != 0) and
       (_control_channel_listeners.size() != 0)
    then
      _connections.inform_cluster_of_join()
    else
      _waiting_to_finish_join = true
    end

  be inform_worker_of_boundary_count(target_worker: String) =>
    // There is one boundary per source plus the canonical boundary
    let count = _sources.size() + 1
    _connections.inform_worker_of_boundary_count(target_worker, count)

  be reconnect_source_boundaries(target_worker: String) =>
    for source in _sources.values() do
      source.reconnect_boundary(target_worker)
    end

  //////////////
  // NEW WORKER PARTITION MIGRATION
  //////////////
  be migrate_onto_new_worker(new_worker: String) =>
    """
    Called when a new worker joins the cluster and we are ready to start
    the partition migration process. We first trigger a pause to allow
    in-flight messages to finish processing.
    """
    _migrating = true
    _stop_the_world(new_worker)
    let timers = Timers
    let timer = Timer(PauseBeforeMigrationNotify(this, new_worker),
      _stop_the_world_pause)
    timers(consume timer)

  fun ref _stop_the_world(new_worker: String) =>
    """
    We currently stop all message processing before migrating partitions and
    updating routers/routes.
    """
    @printf[I32]("~~~Stopping message processing for state migration.~~~\n".cstring())
    _migration_target_ack_list.set(new_worker)
    _mute_request(_worker_name)
    _connections.stop_the_world(recover [new_worker] end)

  be resume_the_world() =>
    _resume_the_world()

  fun ref _resume_the_world() =>
    """
    Migration is complete and we're ready to resume message processing
    """
    _resume_all_local()
    _migrating = false
    @printf[I32]("~~~Resuming message processing.~~~\n".cstring())

  be begin_migration(target_worker: String) =>
    """
    Begin partition migration
    """
    if _partition_routers.size() == 0 then
      //no steps have been migrated
      @printf[I32]("Resuming message processing immediately. No partitions to migrate.\n".cstring())
      _resume_the_world()
    end
    @printf[I32]("Migrating partitions to %s\n".cstring(), target_worker.cstring())
    for state_name in _partition_routers.keys() do
      _migrate_partition_steps(state_name, target_worker)
    end

  be step_migration_complete(step_id: U128) =>
    """
    Step with provided step id has been created on another worker.
    """
    _step_waiting_list.unset(step_id)
    if (_step_waiting_list.size() == 0) then
      _send_migration_batch_complete()
    end

  fun _send_migration_batch_complete() =>
    """
    Inform migration target that the entire migration batch has been sent.
    """
    @printf[I32]("--Sending migration batch complete msg to new workers\n".cstring())
    for target in _migration_target_ack_list.values() do
      try
        _outgoing_boundaries(target).send_migration_batch_complete()
      else
        Fail()
      end
    end

  be remote_mute_request(originating_worker: String) =>
    """
    A remote worker requests that we mute all sources and data channel.
    """
    _mute_request(originating_worker)

  fun ref _mute_request(originating_worker: String) =>
    _stopped_worker_waiting_list.set(originating_worker)
    _stop_all_local()

  be remote_unmute_request(originating_worker: String) =>
    """
    A remote worker requests that we unmute all sources and data channel.
    """
    _unmute_request(originating_worker)

  fun ref _unmute_request(originating_worker: String) =>
    _stopped_worker_waiting_list.unset(originating_worker)
    if (_stopped_worker_waiting_list.size() == 0) and _migrating then
      if _migration_target_ack_list.size() == 0 then
        _resume_the_world()
      else
        // We should only unmute ourselves once _migration_target_ack_list is
        // empty, which means we should never reach this line
        Fail()
      end
    end

  be process_migrating_target_ack(target: String) =>
    """
    Called when we receive a migration batch ack from the new worker
    (i.e. migration target) indicating it's ready to receive data messages
    """
    @printf[I32]("--Processing migration batch complete ack from %s\n".cstring(), target.cstring())
    _migration_target_ack_list.unset(target)

    if _migration_target_ack_list.size() == 0 then
      @printf[I32]("--All new workers have acked migration batch complete\n".cstring(), target.cstring())
      _connections.request_cluster_unmute()
      _unmute_request(_worker_name)
    end

  fun _stop_all_local() =>
    """
    Mute all sources and data channel.
    """
    @printf[I32]("Muting any local sources.\n".cstring())
    for source in _sources.values() do
      source.mute(_dummy_consumer)
    end

  fun _resume_all_local() =>
    """
    Unmute all sources and data channel.
    """
    @printf[I32]("Unmuting any local sources.\n".cstring())
    for source in _sources.values() do
      source.unmute(_dummy_consumer)
    end

  be try_to_resume_processing_immediately() =>
    if _step_waiting_list.size() == 0 then
      _send_migration_batch_complete()
    end

  be ack_migration_batch_complete(sender_name: String) =>
    """
    Called when a new (joining) worker needs to ack to worker sender_name that
    it's ready to start receiving messages after migration
    """
    _connections.ack_migration_batch_complete(sender_name)

  fun _migrate_partition_steps(state_name: String, target_worker: String) =>
    """
    Called to initiate migrating partition steps to a target worker in order
    to rebalance.
    """
    try
      @printf[I32]("Migrating steps for %s partition to %s\n".cstring(),
        state_name.cstring(), target_worker.cstring())
      let boundary = _outgoing_boundaries(target_worker)
      let partition_router = _partition_routers(state_name)
      partition_router.rebalance_steps(boundary, target_worker,
        _worker_count(), state_name, this)
    else
      Fail()
    end

  be add_to_step_waiting_list(step_id: U128) =>
    _step_waiting_list.set(step_id)


  /////
  // Step moved off this worker or new step added to another worker
  /////
  be move_step_to_proxy(id: U128, proxy_address: ProxyAddress) =>
    """
    Called when a stateless step has been migrated off this worker to another
    worker
    """
    _move_step_to_proxy(id, proxy_address)

  be move_stateful_step_to_proxy[K: (Hashable val & Equatable[K] val)](
    id: U128, proxy_address: ProxyAddress, key: K, state_name: String)
  =>
    """
    Called when a stateful step has been migrated off this worker to another
    worker
    """
    _add_state_proxy_to_partition_router[K](proxy_address, key, state_name)
    _move_step_to_proxy(id, proxy_address)

  fun ref _move_step_to_proxy(id: U128, proxy_address: ProxyAddress) =>
    """
    Called when a step has been migrated off this worker to another worker
    """
    _remove_step_from_data_router(id)
    _add_proxy_to_omni_router(id, proxy_address)

  be add_state_proxy[K: (Hashable val & Equatable[K] val)](id: U128,
    proxy_address: ProxyAddress, key: K, state_name: String)
  =>
    """
    Called when a stateful step has been added to another worker
    """
    _add_state_proxy_to_partition_router[K](proxy_address, key, state_name)
    _add_proxy_to_omni_router(id, proxy_address)

  fun ref _add_state_proxy_to_partition_router[
    K: (Hashable val & Equatable[K] val)](proxy_address: ProxyAddress,
    key: K, state_name: String)
  =>
    try
      let proxy_router = ProxyRouter(_worker_name,
        _outgoing_boundaries(proxy_address.worker), proxy_address, _auth)
      let partition_router =
        _partition_routers(state_name).update_route[K](key, proxy_router)
      _partition_routers(state_name) = partition_router
      _distribute_partition_router(partition_router)
    else
      Fail()
    end

  fun ref _remove_step_from_data_router(id: U128) =>
    try
      let moving_step = _data_router.step_for_id(id)

      let new_data_router = _data_router.remove_route(id)
      _data_router = new_data_router
      _distribute_data_router()
    else
      Fail()
    end

  fun ref _add_proxy_to_omni_router(id: U128,
    proxy_address: ProxyAddress)
  =>
    match _omni_router
    | let o: OmniRouter =>
      let new_omni_router = o.update_route_to_proxy(id, proxy_address)
      for step in _omni_router_steps.values() do
        step.update_omni_router(new_omni_router)
      end
      _omni_router = new_omni_router
    else
      Fail()
    end

  /////
  // Step moved onto this worker
  /////
  be move_proxy_to_step(id: U128, target: Consumer,
    source_worker: String)
  =>
    """
    Called when a stateless step has been migrated to this worker from another
    worker
    """
    _move_proxy_to_step(id, target, source_worker)

  be move_proxy_to_stateful_step[K: (Hashable val & Equatable[K] val)](
    id: U128, target: Consumer, key: K, state_name: String,
    source_worker: String)
  =>
    """
    Called when a stateful step has been migrated to this worker from another
    worker
    """
    try
      match target
      | let step: Step =>
        match _omni_router
        | let omni_router: OmniRouter =>
          step.update_omni_router(omni_router)
        else
          Fail()
        end
        let partition_router =
          _partition_routers(state_name).update_route[K](key, step)
        _distribute_partition_router(partition_router)
        // Add routes to state computation targets to state step
        match _pre_state_data
        | let psds: Array[PreStateData] val =>
          for psd in psds.values() do
            if psd.state_name() == state_name then
              match psd.target_id()
              | let tid: U128 =>
                let target_router = DirectRouter(_data_router.step_for_id(tid))
                step.register_routes(target_router,
                  psd.forward_route_builder())
              end
            end
          end
        else
          Fail()
        end
        _partition_routers(state_name) = partition_router
      else
        Fail()
      end
    else
      Fail()
    end
    _move_proxy_to_step(id, target, source_worker)
    _connections.notify_cluster_of_new_stateful_step[K](id, key, state_name,
      recover [source_worker] end)

  fun ref _move_proxy_to_step(id: U128, target: Consumer,
    source_worker: String)
  =>
    """
    Called when a step has been migrated to this worker from another worker
    """
    let new_data_router = _data_router.add_route(id, target)
    _data_router = new_data_router
    _distribute_data_router()

    match _omni_router
    | let o: OmniRouter =>
      let new_omni_router = o.update_route_to_step(id, target)
      for step in _omni_router_steps.values() do
        step.update_omni_router(new_omni_router)
      end
      _omni_router = new_omni_router
    else
      Fail()
    end

class PauseBeforeMigrationNotify is TimerNotify
  let _registry: RouterRegistry
  let _target_worker: String

  new iso create(registry: RouterRegistry, target_worker: String) =>
    _registry = registry
    _target_worker = target_worker

  fun ref apply(timer: Timer, count: U64): Bool =>
    _registry.begin_migration(_target_worker)
    false

// TODO: Replace using this with the badly named SetIs once we address a bug
// in SetIs where unsetting doesn't reduce set size for type SetIs[String].
// This bug does not exist on the latest Pony compiler, only our fork.
class _StringSet
  let _map: Map[String, String] = _map.create()

  fun ref set(s: String) =>
    _map(s) = s

  fun ref unset(s: String) =>
    try _map.remove(s) end

  fun size(): USize =>
    _map.size()

  fun values(): MapValues[String, String, HashEq[String],
    this->HashMap[String, String, HashEq[String]]]^
  =>
    _map.values()

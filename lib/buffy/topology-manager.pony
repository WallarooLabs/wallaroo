use "net"
use "collections"
use "buffy/messages"
use "random"

actor TopologyManager
  let _env: Env
  let _auth: AmbientAuth
  let _step_manager: StepManager
  let _coordinator: Coordinator
  let _name: String
  let _worker_count: USize
  let _workers: Map[String, TCPConnection tag] = Map[String, TCPConnection tag]
  let _worker_addrs: Map[String, (String, String)] = Map[String, (String, String)]
  let _topology: Topology val
  // Keep track of how many workers identified themselves
  var _hellos: USize = 0
  // Keep track of how many workers acknowledged they're running their
  // part of the topology
  var _acks: USize = 0
  let _leader_host: String
  let _leader_service: String
  let _phone_home_connection: TCPConnection

  new create(env: Env, auth: AmbientAuth, name: String, worker_count: USize,
    leader_host: String, leader_service: String, phone_home_conn: TCPConnection,
    step_manager: StepManager, coordinator: Coordinator, topology: Topology val) =>
    _env = env
    _auth = auth
    _step_manager = step_manager
    _coordinator = coordinator
    _name = name
    _worker_count = worker_count
    _topology = topology
    _leader_host = leader_host
    _leader_service = leader_service
    _phone_home_connection = phone_home_conn
    _worker_addrs(name) = (leader_host, leader_service)

    let message = WireMsgEncoder.ready(_name)
    _phone_home_connection.write(message)

    if _worker_count == 0 then _complete_initialization() end

  be assign_name(conn: TCPConnection tag, node_name: String,
    host: String, service: String) =>
    _workers(node_name) = conn
    _worker_addrs(node_name) = (host, service)
    _env.out.print("Identified worker " + node_name)
    _hellos = _hellos + 1
    if _hellos == _worker_count then
      _env.out.print("_--- All workers accounted for! ---_")
      _initialize_topology()
    end

  fun ref next_guid(dice: Dice): I32 =>
    dice(1, I32.max_value().u64()).i32()

  // Currently assigns steps in pipeline using round robin among nodes
  fun ref _initialize_topology() =>
    let repeated_steps = Map[I32, I32] // map from pipeline id to step id
    let seed: U64 = 323437823
    let dice = Dice(MT(seed))
    try
      let nodes = Array[String]
      nodes.push(_name)
      let keys = _workers.keys()
      for key in keys do
        nodes.push(key)
      end

      var cur_source_id: I32 = 0
      var cur_sink_id: I32 = 0
      var step_id: I32 = cur_source_id
      var proxy_step_id: I32 = next_guid(dice)
      var proxy_step_target_id: I32 = next_guid(dice)

      for pipeline in _topology.pipelines.values() do
        var count: USize = 0
        // Round robin node assignment
        while count < pipeline.size() do
          let cur_node_idx = count % nodes.size()
          let cur_node = nodes(count % nodes.size())
          let next_node_idx = (cur_node_idx + 1) % nodes.size()
          let next_node = nodes((cur_node_idx + 1) % nodes.size())
          let next_node_addr =
            if next_node_idx == 0 then
              (_leader_host, _leader_service)
            else
              _worker_addrs(next_node)
            end
          let pipeline_step: PipelineStep box = pipeline(count)
          if pipeline_step.id() != 0 then
            try
              step_id = repeated_steps(pipeline_step.id())
            else
              repeated_steps(pipeline_step.id()) = step_id
            end
          end

          if (count + 1) < pipeline.size() then
            let next_pipeline_id = pipeline(count + 1).id()
            if next_pipeline_id != 0 then
              try
                proxy_step_target_id = repeated_steps(next_pipeline_id)
              else
                repeated_steps(next_pipeline_id) = proxy_step_target_id
              end
            end
          end

          _env.out.print("Spinning up computation **" + pipeline_step.computation_type() + "** on node \'" + cur_node + "\'")

          if cur_node_idx == 0 then // if cur_node is the leader/source
            let target_conn = _workers(next_node)
            _step_manager.add_step(step_id, pipeline_step.computation_type())
            _step_manager.add_proxy(proxy_step_id, proxy_step_target_id,
              target_conn)
            _step_manager.connect_steps(step_id, proxy_step_id)
          else
            let create_step_msg =
              WireMsgEncoder.spin_up(step_id, pipeline_step.computation_type())
            let create_proxy_msg =
              WireMsgEncoder.spin_up_proxy(proxy_step_id, proxy_step_target_id,
                next_node, next_node_addr._1, next_node_addr._2)
            let connect_msg =
              WireMsgEncoder.connect_steps(step_id, proxy_step_id)

            let conn = _workers(cur_node)
            conn.write(create_step_msg)
            conn.write(create_proxy_msg)
            conn.write(connect_msg)
          end

          count = count + 1
          step_id = proxy_step_target_id
          proxy_step_id = next_guid(dice)
          proxy_step_target_id = next_guid(dice)
        end
        let sink_node_idx = count % nodes.size()
        let sink_node = nodes(sink_node_idx)
        _env.out.print("Spinning up sink on node " + sink_node)

        if sink_node_idx == 0 then // if cur_node is the leader
          _step_manager.add_sink(cur_sink_id, step_id, _auth)
        else
          let create_sink_msg =
            WireMsgEncoder.spin_up_sink(cur_sink_id, step_id)
          let conn = _workers(sink_node)
          conn.write(create_sink_msg)
        end

        cur_source_id = cur_source_id + 1
        cur_sink_id = cur_sink_id + 1
        step_id = cur_source_id
      end

      let finished_msg =
        WireMsgEncoder.initialization_msgs_finished()
      // Send finished_msg to all workers
      for i in Range(1, nodes.size()) do
        let node = nodes(i)
        let next_conn = _workers(node)
        next_conn.write(finished_msg)
      end
    else
      @printf[String]("Buffy Leader: Failed to initialize topology".cstring())
    end

  be update_connection(conn: TCPConnection tag, node_name: String) =>
    _coordinator.add_connection(conn)
    _workers(node_name) = conn

  be ack_initialized() =>
    _acks = _acks + 1
    if _acks == _worker_count then
      _complete_initialization()
    end

  fun _complete_initialization() =>
    _env.out.print("_--- Topology successfully initialized ---_")
    try
      let env = _env
      let auth = env.root as AmbientAuth
      let name = _name

      let message = WireMsgEncoder.topology_ready(_name)
      _phone_home_connection.write(message)
    else
      _env.out.print("Couldn't get ambient authority when completing "
        + "initialization")
    end

  be shutdown() =>
    let message = WireMsgEncoder.shutdown(_name)
    for (key, conn) in _workers.pairs() do
      conn.write(message)
    end
    _coordinator.finish_shutdown()

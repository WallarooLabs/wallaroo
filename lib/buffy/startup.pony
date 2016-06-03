use "net"
use "options"
use "collections"
use "buffy/metrics"
use "spike"
use "./network"
use "./topology"
use "buffy/flusher"
use "time"

actor Startup
  new create(env: Env, topology: Topology val, source_count: USize) =>
    var is_worker = true
    var worker_count: USize = 0
    var node_name: String = "0"
    var phone_home_addr = Array[String]
    var metrics_addr = Array[String]
    var metrics_delay: U64 = 1_000_000_000
    var options = Options(env)
    var leader_control_addr = Array[String]
    var leader_data_addr = Array[String]
    var source_addrs = Array[String]
    var sink_addrs = Array[String]

    var spike_delay = false
    var spike_drop = false
    var spike_seed: U64 = Time.millis()

    options
      .add("leader", "l", None)
      .add("worker_count", "w", I64Argument)
      .add("phone_home", "p", StringArgument)
      .add("name", "n", StringArgument)
      // Comma-delimited source and sink addresses.
      // e.g. --source 127.0.0.1:6000,127.0.0.1:7000
      .add("leader-control-address", "", StringArgument)
      .add("leader-data-address", "", StringArgument)
      .add("source", "", StringArgument)
      .add("sink", "", StringArgument)
      .add("metrics", "", StringArgument)
      .add("metrics-delay", "", F64Argument)
      .add("spike-delay", "", None)
      .add("spike-drop", "", None)
      .add("spike-seed", "", I64Argument)

    for option in options do
      match option
      | ("leader", None) => is_worker = false
      | ("leader-control-address", let arg: String) =>
        leader_control_addr = arg.split(":")
      | ("leader-data-address", let arg: String) =>
        leader_data_addr = arg.split(":")
      | ("worker_count", let arg: I64) => worker_count = arg.usize()
      | ("phone_home", let arg: String) => phone_home_addr = arg.split(":")
      | ("name", let arg: String) => node_name = arg
      | ("source", let arg: String) => source_addrs.append(arg.split(","))
      | ("sink", let arg: String) => sink_addrs.append(arg.split(","))
      | ("metrics", let arg: String) => metrics_addr = arg.split(":")
      | ("metrics-delay", let arg: F64) =>
        metrics_delay = (arg*1_000_000_000).u64()
      | ("spike-delay", None) =>
        env.out.print("%%SPIKE-DELAY%%")
        spike_delay = true
      | ("spike-drop", None) =>
        if not is_worker then
          env.out.print("Spike drop not currently supported on leader.")
        else
          env.out.print("%%SPIKE-DROP%%")
          spike_drop = true
        end
      | ("spike-seed", let arg: I64) => spike_seed = arg.u64()
      end
    end

    var args = options.remaining()

    try
      if not is_worker then node_name = "leader" end
      let leader_control_host = leader_control_addr(0)
      let leader_control_service = leader_control_addr(1)
      let leader_data_host = leader_data_addr(0)
      let leader_data_service = leader_data_addr(1)
      env.out.print("Using Spike seed " + spike_seed.string())
      let spike_config = SpikeConfig(spike_delay, spike_drop, spike_seed)
      let auth = env.root as AmbientAuth
      let stdout: StdStream = env.out
      let stderr: StdStream = env.err


      let sinks: Map[U64, (String, String)] iso =
        recover Map[U64, (String, String)] end

      for i in Range(0, sink_addrs.size()) do
        let sink_addr: Array[String] = sink_addrs(i).split(":")
        let sink_host = sink_addr(0)
        let sink_service = sink_addr(1)
        sinks(i.u64()) = (sink_host, sink_service)
      end

      let metrics_collector =
        if metrics_addr.size() > 0 then
          let metrics_host = metrics_addr(0)
          let metrics_service = metrics_addr(1)

          let metrics_notifier: TCPConnectionNotify iso =
            MetricsCollectorConnectNotify(auth, stdout, stderr)
          let metrics_conn: TCPConnection =
            TCPConnection(auth, consume metrics_notifier, metrics_host,
                          metrics_service)

          MetricsCollector(stderr, auth, node_name, metrics_conn)
        else
          MetricsCollector(stderr, auth, node_name)
        end

        // start a timer to flush the receiver
        let delay' = recover val metrics_delay end
        Flusher(metrics_collector, delay')

      let step_manager = StepManager(env, auth, node_name, consume sinks,
        metrics_collector)

      let coordinator: Coordinator = Coordinator(node_name, env, auth,
        leader_control_host, leader_control_service, leader_data_host,
        leader_data_service, step_manager, spike_config, metrics_collector,
        is_worker)

      let phone_home_host = phone_home_addr(0)
      let phone_home_service = phone_home_addr(1)

      let phone_home_conn: TCPConnection = TCPConnection(auth,
        HomeConnectNotify(env, auth, node_name, coordinator), phone_home_host,
          phone_home_service)

      coordinator.add_phone_home_connection(phone_home_conn)

      if is_worker then
        coordinator.add_listener(TCPListener(auth,
          WorkerControlNotifier(env, auth, node_name, leader_control_host,
            leader_control_service, coordinator, metrics_collector)))
        coordinator.add_listener(TCPListener(auth,
          WorkerIntraclusterDataNotifier(env, auth, node_name,
            leader_control_host, leader_control_service, coordinator,
            spike_config)))
      else
        if source_addrs.size() != source_count then
          env.out.print("There are " + source_count.string() + " sources but "
            + source_addrs.size().string() + " source addresses specified.")
          return
        end
        // Set up source listeners
        for i in Range(0, source_count) do
          let source_addr: Array[String] = source_addrs(i).split(":")
          let source_host = source_addr(0)
          let source_service = source_addr(1)
          let source_notifier: TCPListenNotify iso = SourceNotifier(env, auth,
            source_host, source_service, i.u64(), step_manager, coordinator,
            metrics_collector)
          coordinator.add_listener(TCPListener(auth, consume source_notifier,
            source_host, source_service))
        end
        // Set up leader listener
        let topology_manager: TopologyManager = TopologyManager(env, auth,
          node_name, worker_count, leader_control_host, leader_control_service,
          leader_data_host, leader_data_service, coordinator, topology)

        coordinator.add_topology_manager(topology_manager)

        let control_notifier: TCPListenNotify iso =
          LeaderControlNotifier(env, auth, node_name, coordinator,
            topology_manager, metrics_collector)
        coordinator.add_listener(TCPListener(auth, consume control_notifier,
          leader_control_host, leader_control_service))
        let data_notifier: TCPListenNotify iso =
          LeaderIntraclusterDataNotifier(env, auth, node_name, coordinator,
          spike_config)
        coordinator.add_listener(TCPListener(auth, consume data_notifier,
          leader_data_host, leader_data_service))
      end

      if is_worker then
        env.out.print("**Buffy Worker " + node_name + "**")
      else
        env.out.print("**Buffy Leader " + node_name + " control: "
          + leader_control_host + ":" + leader_control_service + "**")
        env.out.print("**Buffy Leader " + node_name + " data: "
          + leader_data_host + ":" + leader_data_service + "**")
        env.out.print("** -- Looking for " + worker_count.string()
          + " workers --**")
      end
    else
      TestMain(env)
      env.out.print("Parameters: leader_address [-l -w <worker_count>"
        + "-p <phone_home_address> --id <node_name>]")
    end

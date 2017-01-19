use "collections"
use "net"
use "wallaroo/boundary"
use "wallaroo/fail"
use "wallaroo/messages"
use "wallaroo/routing"
use "wallaroo/tcp-sink"

interface Router
  fun route[D: Any val](metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, i_msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  fun routes(): Array[CreditFlowConsumerStep] val

interface RouterBuilder
  fun apply(): Router val

class EmptyRouter
  fun route[D: Any val](metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, i_msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    (true, true, latest_ts)

  fun routes(): Array[CreditFlowConsumerStep] val =>
    recover val Array[CreditFlowConsumerStep] end

class DirectRouter
  let _target: CreditFlowConsumerStep tag

  new val create(target: CreditFlowConsumerStep tag) =>
    _target = target

  fun route[D: Any val](metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, i_msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    ifdef "trace" then
      @printf[I32]("Rcvd msg at DirectRouter\n".cstring())
    end

    let might_be_route = producer.route_to(_target)
    match might_be_route
    | let r: Route =>
      ifdef "trace" then
        @printf[I32]("DirectRouter found Route\n".cstring())
      end
      let keep_sending = r.run[D](metric_name, pipeline_time_spent, data,
        // hand down producer so we can call _next_sequence_id()
        producer,
        // incoming envelope
        i_origin, i_msg_uid, i_frac_ids, i_seq_id, i_route_id,
        latest_ts, metrics_id, worker_ingress_ts)
      (false, keep_sending, latest_ts)
    else
      // TODO: What do we do if we get None?
      (true, true, latest_ts)
    end


  fun routes(): Array[CreditFlowConsumerStep] val =>
    recover val [_target] end

  fun has_sink(): Bool =>
    match _target
    | let tcp: TCPSink =>
      true
    else
      false
    end

class ProxyRouter
  let _worker_name: String
  let _target: CreditFlowConsumerStep tag
  let _target_proxy_address: ProxyAddress val
  let _auth: AmbientAuth

  new val create(worker_name: String, target: CreditFlowConsumerStep tag,
    target_proxy_address: ProxyAddress val, auth: AmbientAuth)
  =>
    _worker_name = worker_name
    _target = target
    _target_proxy_address = target_proxy_address
    _auth = auth

  fun route[D: Any val](metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    ifdef "trace" then
      @printf[I32]("Rcvd msg at ProxyRouter\n".cstring())
    end

    let might_be_route = producer.route_to(_target)
    match might_be_route
    | let r: Route =>
      ifdef "trace" then
        @printf[I32]("DirectRouter found Route\n".cstring())
      end
      let delivery_msg = ForwardMsg[D](
        _target_proxy_address.step_id,
        _worker_name, data, metric_name,
        _target_proxy_address,
        msg_uid, i_frac_ids)

      let keep_sending = r.forward(delivery_msg, pipeline_time_spent, producer,
        i_origin, msg_uid, i_frac_ids, i_seq_id, i_route_id, latest_ts,
        metrics_id, metric_name, worker_ingress_ts)

      (false, keep_sending, latest_ts)
    else
      // TODO: What do we do if we get None?
      (true, true, latest_ts)
    end

  fun copy_with_new_target_id(target_id: U128): ProxyRouter val =>
    ProxyRouter(_worker_name,
      _target,
      ProxyAddress(_target_proxy_address.worker, target_id),
      _auth)

  fun routes(): Array[CreditFlowConsumerStep] val =>
    recover val [_target] end

trait OmniRouter
  fun route_with_target_id[D: Any val](target_id: U128,
    metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)

class EmptyOmniRouter is OmniRouter
  fun route_with_target_id[D: Any val](target_id: U128,
    metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    @printf[I32]("route_with_target_id() was called on an EmptyOmniRouter\n".cstring())
    (true, true, latest_ts)

class StepIdRouter is OmniRouter
  let _worker_name: String
  let _data_routes: Map[U128, CreditFlowConsumerStep tag] val
  let _step_map: Map[U128, (ProxyAddress val | U128)] val
  let _outgoing_boundaries: Map[String, OutgoingBoundary] val

  new val create(worker_name: String,
    data_routes: Map[U128, CreditFlowConsumerStep tag] val,
    step_map: Map[U128, (ProxyAddress val | U128)] val,
    outgoing_boundaries: Map[String, OutgoingBoundary] val)
  =>
    _worker_name = worker_name
    _data_routes = data_routes
    _step_map = step_map
    _outgoing_boundaries = outgoing_boundaries

  fun route_with_target_id[D: Any val](target_id: U128,
    metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    ifdef "trace" then
      @printf[I32]("Rcvd msg at OmniRouter\n".cstring())
    end

    try
      // Try as though this target_id step exists on this worker
      let target = _data_routes(target_id)

      let might_be_route = producer.route_to(target)
      match might_be_route
      | let r: Route =>
        ifdef "trace" then
          @printf[I32]("OmniRouter found Route to Step\n".cstring())
        end
        let keep_sending = r.run[D](metric_name, pipeline_time_spent, data,
          // hand down producer so we can update route_id
          producer,
          // incoming envelope
          i_origin, msg_uid, i_frac_ids, i_seq_id, i_route_id,
          latest_ts, metrics_id, worker_ingress_ts)

        (false, keep_sending, latest_ts)
      else
        // No route for this target
        (true, true, latest_ts)
      end
    else
      // This target_id step exists on another worker
      try
        match _step_map(target_id)
        | let pa: ProxyAddress val =>
          try
            // Try as though we have a reference to the right boundary
            let boundary = _outgoing_boundaries(pa.worker)
            let might_be_route = producer.route_to(boundary)
            match might_be_route
            | let r: Route =>
              ifdef "trace" then
                @printf[I32]("OmniRouter found Route to OutgoingBoundary\n"
                  .cstring())
              end
              let delivery_msg = ForwardMsg[D](pa.step_id,
                _worker_name, data, metric_name,
                pa, msg_uid, i_frac_ids)

              let keep_sending = r.forward(delivery_msg, pipeline_time_spent,
                producer, i_origin, msg_uid, i_frac_ids,
                i_seq_id, i_route_id, latest_ts, metrics_id, metric_name,
                worker_ingress_ts)
              (false, keep_sending, latest_ts)
            else
              // We don't have a route to this boundary
              ifdef debug then
                @printf[I32]("OmniRouter had no Route\n".cstring())
              end
              (true, true, latest_ts)
            end
          else
            // We don't have a reference to the right outgoing boundary
            ifdef debug then
              @printf[I32]("OmniRouter has no reference to OutgoingBoundary\n".cstring())
            end
            (true, true, latest_ts)
          end
        | let sink_id: U128 =>
          (true, true, latest_ts)
        else
          (true, true, latest_ts)
        end
      else
        // Apparently this target_id does not refer to a valid step id
        ifdef debug then
          @printf[I32]("OmniRouter: target id does not refer to valid step id\n".cstring())
        end
        (true, true, latest_ts)
      end
    end

class DataRouter
  let _data_routes: Map[U128, CreditFlowConsumerStep tag] val
  let _route_ids: Map[U128, RouteId] = _route_ids.create()

  new val create(data_routes: Map[U128, CreditFlowConsumerStep tag] val =
      recover Map[U128, CreditFlowConsumerStep tag] end)
  =>
    _data_routes = data_routes
    var route_id: RouteId = 0
    for step_id in _data_routes.keys() do
      route_id = route_id + 1
      _route_ids(step_id) = route_id
    end

  fun route(d_msg: DeliveryMsg val, pipeline_time_spent: U64,
    origin: DataReceiver ref, seq_id: SeqId, latest_ts: U64, metrics_id: U16,
    worker_ingress_ts: U64)
  =>
    ifdef "trace" then
      @printf[I32]("Rcvd msg at DataRouter\n".cstring())
    end
    let target_id = d_msg.target_id()
    try
      let target = _data_routes(target_id)
      ifdef "trace" then
        @printf[I32]("DataRouter found Step\n".cstring())
      end
      try
        let route_id = _route_ids(target_id)
        d_msg.deliver(pipeline_time_spent, target, origin, seq_id, route_id,
          latest_ts, metrics_id, worker_ingress_ts)
        ifdef "resilience" then
          origin.bookkeeping(route_id, seq_id)
        end
        false
      else
        // This shouldn't happen. If we have a route, we should have a route
        // id.
        Fail()
        false
      end
    else
      ifdef debug then
        @printf[I32]("DataRouter failed to find route\n".cstring())
      end
      Fail()
      true
    end

  fun replay_route(r_msg: ReplayableDeliveryMsg val, pipeline_time_spent: U64,
    origin: Producer, seq_id: SeqId, latest_ts: U64, metrics_id: U16,
    worker_ingress_ts: U64)
  =>
    try
      let target_id = r_msg.target_id()
      let route_id = _route_ids(target_id)
      //TODO: create and deliver envelope
      r_msg.replay_deliver(pipeline_time_spent, _data_routes(target_id),
        origin, seq_id, route_id, latest_ts, metrics_id, worker_ingress_ts)
      false
    else
      ifdef debug then
        @printf[I32]("DataRouter failed to find route on replay\n".cstring())
      end
      Fail()
      true
    end

  fun register_producer(producer: Producer) =>
    for step in _data_routes.values() do
      step.register_producer(producer)
    end

  fun unregister_producer(producer: Producer, credits_returned: ISize) =>
    for step in _data_routes.values() do
      step.unregister_producer(producer, credits_returned)
    end

  fun request_ack(producer: Producer) =>
    for (target_id, r) in _data_routes.pairs() do
      r.request_ack()
    end

  fun route_ids(): Array[RouteId] =>
    let ids: Array[RouteId] = ids.create()
    for id in _route_ids.values() do
      ids.push(id)
    end
    ids

  fun routes(): Array[CreditFlowConsumerStep] val =>
    // TODO: CREDITFLOW - real implmentation?
    recover val Array[CreditFlowConsumerStep] end

  // fun routes(): Array[CreditFlowConsumer tag] val =>
  //   let rs: Array[CreditFlowConsumer tag] trn =
  //     recover Array[CreditFlowConsumer tag] end

  //   for (k, v) in _routes.pairs() do
  //     rs.push(v)
  //   end

  //   consume rs

trait PartitionRouter is Router
  fun local_map(): Map[U128, Step] val
  fun register_routes(router: Router val, route_builder: RouteBuilder val)

trait AugmentablePartitionRouter[Key: (Hashable val & Equatable[Key] val)] is
  PartitionRouter
  fun clone_and_set_input_type[NewIn: Any val](
    new_p_function: PartitionFunction[NewIn, Key] val,
    new_default_router: (Router val | None) = None): PartitionRouter val

class LocalPartitionRouter[In: Any val,
  Key: (Hashable val & Equatable[Key] val)] is AugmentablePartitionRouter[Key]
  let _local_map: Map[U128, Step] val
  let _step_ids: Map[Key, U128] val
  let _partition_routes: Map[Key, (Step | ProxyRouter val)] val
  let _partition_function: PartitionFunction[In, Key] val
  let _default_router: (Router val | None)

  new val create(local_map': Map[U128, Step] val,
    s_ids: Map[Key, U128] val,
    partition_routes: Map[Key, (Step | ProxyRouter val)] val,
    partition_function: PartitionFunction[In, Key] val,
    default_router: (Router val | None) = None)
  =>
    _local_map = local_map'
    _step_ids = s_ids
    _partition_routes = partition_routes
    _partition_function = partition_function
    _default_router = default_router

  fun route[D: Any val](metric_name: String, pipeline_time_spent: U64, data: D,
    producer: Producer ref,
    i_origin: Producer, i_msg_uid: U128,
    i_frac_ids: None, i_seq_id: SeqId, i_route_id: RouteId,
    latest_ts: U64, metrics_id: U16, worker_ingress_ts: U64): (Bool, Bool, U64)
  =>
    ifdef "trace" then
      @printf[I32]("Rcvd msg at PartitionRouter\n".cstring())
    end
    match data
    // TODO: Using an untyped input wrapper that returns an Any val might
    // cause perf slowdowns and should be reevaluated.
    | let iw: InputWrapper val =>
      match iw.input()
      | let input: In =>
        let key = _partition_function(input)
        try
          match _partition_routes(key)
          | let s: Step =>
            let might_be_route = producer.route_to(s)
            match might_be_route
            | let r: Route =>
              ifdef "trace" then
                @printf[I32]("PartitionRouter found Route\n".cstring())
              end
              let keep_sending =r.run[D](metric_name, pipeline_time_spent, data,
                // hand down producer so we can update route_id
                producer,
                // incoming envelope
                i_origin, i_msg_uid, i_frac_ids, i_seq_id, i_route_id,
                latest_ts, metrics_id, worker_ingress_ts)
              (false, keep_sending, latest_ts)
            else
              // TODO: What do we do if we get None?
              (true, true, latest_ts)
            end
          | let p: ProxyRouter val =>
            p.route[D](metric_name, pipeline_time_spent, data, producer,
              i_origin, i_msg_uid, i_frac_ids, i_seq_id, i_route_id,
              latest_ts, metrics_id, worker_ingress_ts)
          else
            // No step or proxyrouter
            (true, true, latest_ts)
          end
        else
          // There is no entry for this key!
          // If there's a default, use that
          match _default_router
          | let r: Router val =>
            ifdef "trace" then
              @printf[I32]("PartitionRouter sending to default step as there was no entry for key\n".cstring())
            end
            r.route[In](metric_name, pipeline_time_spent, input, producer,
              i_origin, i_msg_uid, i_frac_ids, i_seq_id, i_route_id,
              latest_ts, metrics_id, worker_ingress_ts)
          else
            ifdef debug then
              @printf[I32](("LocalPartitionRouter.route: No entry for this" +
                "key and no default\n\n").cstring())
            end
            (true, true, latest_ts)
          end
        end
      else
        // InputWrapper doesn't wrap In
        ifdef debug then
          @printf[I32]("LocalPartitionRouter.route: InputWrapper doesn't contain data of type In\n".cstring())
        end
        (true, true, latest_ts)
      end
    else
      (true, true, latest_ts)
    end

  fun clone_and_set_input_type[NewIn: Any val](
    new_p_function: PartitionFunction[NewIn, Key] val,
    new_d_router: (Router val | None) = None): PartitionRouter val
  =>
    match new_d_router
    | let dr: Router val =>
      LocalPartitionRouter[NewIn, Key](_local_map, _step_ids,
        _partition_routes, new_p_function, dr)
    else
      LocalPartitionRouter[NewIn, Key](_local_map, _step_ids,
        _partition_routes, new_p_function, _default_router)
    end

  fun register_routes(router: Router val, route_builder: RouteBuilder val) =>
    for r in _partition_routes.values() do
      match r
      | let step: Step =>
        step.register_routes(router, route_builder)
      end
    end

  fun routes(): Array[CreditFlowConsumerStep] val =>
    // TODO: CREDITFLOW we need to handle proxies once we have boundary actors
    let cs: Array[CreditFlowConsumerStep] trn =
      recover Array[CreditFlowConsumerStep] end

    for s in _partition_routes.values() do
      match s
      | let step: Step =>
        cs.push(step)
      end
    end

    consume cs

  fun local_map(): Map[U128, Step] val => _local_map

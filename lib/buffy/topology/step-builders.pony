use "collections"
use "buffy/messages"
use "net"
use "buffy/metrics"
use "time"

trait BasicStepBuilder
  fun apply(): BasicStep tag
  fun shared_state_step_builder(): BasicStepBuilder val => EmptyStepBuilder

trait BasicStateStepBuilder is BasicStepBuilder
  fun state_id(): U64

trait SinkBuilder
  fun apply(conns: Array[TCPConnection] iso, metrics_collector: MetricsCollector)
    : BasicStep tag
  fun is_state_builder(): Bool => false

trait BasicOutputStepBuilder[Out: Any val] is BasicStepBuilder

trait ThroughStepBuilder[In: Any val, Out: Any val]
  is BasicOutputStepBuilder[Out]

class SourceBuilder[Out: Any val]
  is ThroughStepBuilder[String, Out]
  let _parser: Parser[Out] val

  new val create(p: Parser[Out] val) =>
    _parser = p

  fun apply(): BasicStep tag =>
    Source[Out](_parser)

class StepBuilder[In: Any val, Out: Any val]
  is ThroughStepBuilder[In, Out]
  let _computation_builder: ComputationBuilder[In, Out] val

  new val create(c: ComputationBuilder[In, Out] val) =>
    _computation_builder = c

  fun apply(): BasicStep tag =>
    Step[In, Out](_computation_builder())

class MapStepBuilder[In: Any val, Out: Any val]
  is ThroughStepBuilder[In, Out]
  let _computation_builder: MapComputationBuilder[In, Out] val

  new val create(c: MapComputationBuilder[In, Out] val) =>
    _computation_builder = c

  fun apply(): BasicStep tag =>
    MapStep[In, Out](_computation_builder())

class PartitionBuilder[In: Any val, Out: Any val]
  is ThroughStepBuilder[In, Out]
  let _step_builder: BasicStepBuilder val
  let _partition_function: PartitionFunction[In] val

  new val create(c: ComputationBuilder[In, Out] val, pf: PartitionFunction[In] val) =>
    _step_builder = StepBuilder[In, Out](c)
    _partition_function = pf

  new val with_step_builder(sb: BasicStepBuilder val, pf: PartitionFunction[In] val) =>
    _step_builder = sb
    _partition_function = pf

  fun apply(): BasicStep tag =>
    Partition[In, Out](_step_builder, _partition_function)

class SharedStatePartitionBuilder[State: Any #read]
  is BasicStepBuilder
  let _step_builder: BasicStepBuilder val
  let _initialization_map: Map[U64, {(): State} val] val
  let _initialize_at_start: Bool

  new val create(sb: BasicStepBuilder val,
    init_map: Map[U64, {(): State} val] val, init_at_start: Bool) =>
    _step_builder = sb
    _initialization_map = init_map
    _initialize_at_start = init_at_start

  fun apply(): BasicStep tag =>
    StatePartition[State](_step_builder, _initialization_map,
      _initialize_at_start)

class StateStepBuilder[In: Any val, Out: Any val, State: Any #read]
  is (ThroughStepBuilder[In, Out] & BasicStateStepBuilder)
  let _comp_builder: ComputationBuilder[In, StateComputation[Out, State] val] val
  let _shared_state_step_builder: SharedStateStepBuilder[State] val
  let _state_id: U64

  new val create(comp_builder: ComputationBuilder[In,
    StateComputation[Out, State] val] val,
    state_initializer: StateInitializer[State] val, s_id: U64) =>
    _comp_builder = comp_builder
    _shared_state_step_builder =
      SharedStateStepBuilder[State](state_initializer)
    _state_id = s_id

  fun apply(): BasicStateStep tag =>
    StateStep[In, Out, State](_comp_builder, _state_id)

  fun state_id(): U64 => _state_id
  fun shared_state_step_builder(): BasicStepBuilder val =>
    _shared_state_step_builder

class SharedStateStepBuilder[State: Any #read]
  is BasicStepBuilder
  let _state_initializer: StateInitializer[State] val

  new val create(state_initializer: StateInitializer[State] val) =>
    _state_initializer = state_initializer

  fun apply(): BasicStep tag =>
    SharedStateStep[State](_state_initializer)

class StatePartitionBuilder[In: Any val, Out: Any val, State: Any #read]
  is (ThroughStepBuilder[In, Out] & BasicStateStepBuilder)
  let _partition_function: PartitionFunction[In] val
  let _comp_builder: ComputationBuilder[In, StateComputation[Out, State] val] val
  let _shared_state_step_builder: BasicStepBuilder val
  let _state_id: U64

  new val create(comp_builder: ComputationBuilder[In,
    StateComputation[Out, State] val] val,
    state_initializer: StateInitializer[State] val,
    pf: PartitionFunction[In] val, s_id: U64,
    init_map: Map[U64, {(): State} val] val, init_at_start: Bool)
    =>
    _comp_builder = comp_builder
    _partition_function = pf
    _shared_state_step_builder =
      SharedStatePartitionBuilder[State](
        SharedStateStepBuilder[State](state_initializer), init_map, init_at_start)
    _state_id = s_id

  fun apply(): BasicStep tag =>
    StateStep[In, Out, State](_comp_builder, _state_id, _partition_function)

  fun state_id(): U64 => _state_id
  fun shared_state_step_builder(): BasicStepBuilder val =>
    _shared_state_step_builder

primitive EmptyStepBuilder is BasicStepBuilder
  fun apply(): BasicStep tag => EmptyStep

class ExternalConnectionBuilder[In: Any val] is SinkBuilder
  let _stringify: Stringify[In] val

  new val create(stringify: Stringify[In] val) =>
    _stringify = stringify

  fun apply(conns: Array[TCPConnection] iso, metrics_collector: MetricsCollector)
    : BasicStep tag =>
    ExternalConnection[In](_stringify, consume conns, metrics_collector)

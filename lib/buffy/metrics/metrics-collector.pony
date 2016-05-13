use "collections"
use "net"
use "buffy/messages"
use "sendence/bytes"

type _StepType is U32
type _StepId is U32

actor MetricsCollector
  let _env: Env
  let _node_name: String
  var _step_reports: Map[_StepId, Array[StepMetricsReport val]] =
  	Map[_StepId, Array[StepMetricsReport val]]
  var _step_count: USize = 0
  var _boundary_reports: Array[BoundaryMetricsReport val] =
  	Array[BoundaryMetricsReport val]
  let _conn: (TCPConnection | None)

	new create(env: Env, node_name: String, conn: (TCPConnection | None) = None) =>
	  _env = env
	  _node_name = node_name
	  _conn = conn

	be report_step_metrics(s_id: I32, start_time: U64, end_time: U64) =>
	  let step_id = s_id.u32()
	  try
	    _step_reports(step_id).push(StepMetricsReport(start_time, end_time))
	    _step_count = _step_count + 1
	  else
	    let arr = Array[StepMetricsReport val]
	    arr.push(StepMetricsReport(start_time, end_time))
	    _step_reports(step_id) = arr
	    _step_count = _step_count + 1
		end

	  if _step_count > 10 then
	  	_send_step_metrics_to_receiver()
	  	for key in _step_reports.keys() do
	  		_step_reports(key) = Array[StepMetricsReport val]
			end
	    _step_reports = Map[_StepId, Array[StepMetricsReport val]]
	    _step_count = 0
	  end

	be report_boundary_metrics(boundary_type: I32, msg_id: I32, start_time: U64,
		end_time: U64) =>
		_boundary_reports.push(BoundaryMetricsReport(boundary_type,
			msg_id, start_time, end_time))

	  if _boundary_reports.size() > 10 then
	    _send_boundary_metrics_to_receiver()
	    _boundary_reports = Array[BoundaryMetricsReport val]
	  end

  fun ref _send_step_metrics_to_receiver() =>
  	match _conn
  	| let c: TCPConnection =>
			let encoded = NodeMetricsEncoder(_node_name, _step_reports)
			c.write(Bytes.length_encode(consume encoded))
		end

  fun ref _send_boundary_metrics_to_receiver() =>
  	match _conn
  	| let c: TCPConnection =>
			let encoded = BoundaryMetricsEncoder(_node_name, _boundary_reports)
			c.write(Bytes.length_encode(consume encoded))
		end

class StepReporter
	let _step_id: I32
	let _metrics_collector: MetricsCollector

	new val create(s_id: I32, m_coll: MetricsCollector) =>
		_step_id = s_id
		_metrics_collector = m_coll

	fun report(start_time: U64, end_time: U64) =>
		_metrics_collector.report_step_metrics(_step_id, start_time, end_time)
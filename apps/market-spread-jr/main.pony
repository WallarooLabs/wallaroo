use "collections"
use "net"
use "options"
use "time"
use "buffered"
use "files"
use "sendence/hub"
use "sendence/fix"
use "wallaroo"
use "wallaroo/network"
use "wallaroo/metrics"
use "wallaroo/topology"
use "wallaroo/spike"

actor Main
  new create(env: Env) =>
    Startup(env, MarketSpreadStarter)

primitive MarketSpreadStarter
  fun apply(env: Env, input_addrs: Array[Array[String]], 
    output_addr: Array[String], metrics_addr: Array[String], 
    expected: USize, init_path: String, worker_count: USize,
    initializer: Bool, spike_config: SpikeConfig val) ? 
  =>
    let auth = env.root as AmbientAuth

    let metrics1 = JrMetrics("NBBO")
    let metrics2 = JrMetrics("Orders")

    let connect_auth = TCPConnectAuth(auth)
    let metrics_socket = TCPConnection(connect_auth,
          OutNotify("metrics"),
          metrics_addr(0),
          metrics_addr(1))
    let connect_msg = HubProtocol.connect()
    let metrics_join_msg = HubProtocol.join("metrics:market-spread")
    metrics_socket.writev(connect_msg)
    metrics_socket.writev(metrics_join_msg)

    let reports_socket = TCPConnection(connect_auth,
          SpikeWrapper(OutNotify("rejections"), spike_config),
          output_addr(0),
          output_addr(1))
    let reports_join_msg = HubProtocol.join("reports:market-spread")
    reports_socket.writev(connect_msg)
    reports_socket.writev(reports_join_msg)


    let symbol_actors: Map[String, Step tag] trn = recover trn Map[String, Step tag] end
    for i in legal_symbols().values() do
      let padded = _pad_symbol(i)
      let reporter = MetricsReporter("market-spread", metrics_socket)
      let s = StateRunner[SymbolData](
        lambda(): SymbolData => SymbolData end, consume reporter)
      symbol_actors(padded) = Step(consume s)
    end

    let symbol_to_actor: Map[String, Step tag] val = 
      consume symbol_actors

    let initial_nbbo: Array[Array[U8] val] val = 
      if init_path == "" then
        recover Array[Array[U8] val] end
      else
        _initial_nbbo_msgs(init_path, auth)
      end

    let nbbo_source_builder: {(): Source iso^} val = 
      recover 
        lambda()(symbol_to_actor, metrics_socket, initial_nbbo): 
          Source iso^ 
        =>
          let nbbo_reporter = MetricsReporter("market-spread", metrics_socket)
          StateSource[FixNbboMessage val, SymbolData](
          "Nbbo source", NbboSourceParser, SymbolRouter(symbol_to_actor), 
          UpdateNbbo, consume nbbo_reporter, initial_nbbo)
        end
      end

    let nbboutput_addr = input_addrs(0)

    let listen_auth = TCPListenAuth(env.root as AmbientAuth)
    let nbbo = TCPListener(listen_auth,
          SourceListenerNotify(nbbo_source_builder, metrics1, expected),
          nbboutput_addr(0),
          nbboutput_addr(1))

    let check_order = CheckOrder(reports_socket)
    let order_source: {(): Source iso^} val =
      recover 
        lambda()(symbol_to_actor, metrics_socket, check_order): Source iso^ 
        =>
          let order_reporter = MetricsReporter("market-spread", 
            metrics_socket)
          StateSource[FixOrderMessage val, 
            SymbolData]("Order source", OrderSourceParser, 
            SymbolRouter(symbol_to_actor), check_order, 
              consume order_reporter)
        end
      end

    let order_addr = input_addrs(1)

    let order = TCPListener(listen_auth,
          SourceListenerNotify(order_source, metrics2, (expected/2)),
          order_addr(0),
          order_addr(1))

    @printf[I32]("Expecting %zu total messages\n".cstring(), expected)

  fun _initial_nbbo_msgs(init_path: String, auth: AmbientAuth): 
    Array[Array[U8] val] val ?
  =>
    let nbbo_msgs: Array[Array[U8] val] trn = recover Array[Array[U8] val] end
    let path = FilePath(auth, init_path)
    let init_file = File(path)
    let init_data: Array[U8] val = init_file.read(init_file.size())

    let rb = Reader
    rb.append(init_data)
    var bytes_left = init_data.size()
    while bytes_left > 0 do
      nbbo_msgs.push(rb.block(46).trim(4))
      bytes_left = bytes_left - 46
    end

    init_file.dispose()
    consume nbbo_msgs

  fun _pad_symbol(s: String): String =>
    if s.size() == 4 then
      s
    else
      let diff = 4 - s.size()
      var padded = s
      for i in Range(0, diff) do
        padded = " " + padded
      end
      padded
    end

  fun legal_symbols(): Array[String] =>
      [
"AA",
"BAC",
"AAPL",
"FCX",
"SUNE",
"FB",
"RAD",
"INTC",
"GE",
"WMB",
"S",
"ATML",
"YHOO",
"F",
"T",
"MU",
"PFE",
"CSCO",
"MEG",
"HUN",
"GILD",
"MSFT",
"SIRI",
"SD",
"C",
"NRF",
"TWTR",
"ABT",
"VSTM",
"NLY",
"AMAT",
"X",
"NFLX",
"SDRL",
"CHK",
"KO",
"JCP",
"MRK",
"WFC",
"XOM",
"KMI",
"EBAY",
"MYL",
"ZNGA",
"FTR",
"MS",
"DOW",
"ATVI",
"ORCL",
"JPM",
"FOXA",
"HPQ",
"JBLU",
"RF",
"CELG",
"HST",
"QCOM",
"AKS",
"EXEL",
"ABBV",
"CY",
"VZ",
"GRPN",
"HAL",
"GPRO",
"CAT",
"OPK",
"AAL",
"JNJ",
"XRX",
"GM",
"MHR",
"DNR",
"PIR",
"MRO",
"NKE",
"MDLZ",
"V",
"HLT",
"TXN",
"SWN",
"AGN",
"EMC",
"CVX",
"BMY",
"SLB",
"SBUX",
"NVAX",
"ZIOP",
"NE",
"COP",
"EXC",
"OAS",
"VVUS",
"BSX",
"SE",
"NRG",
"MDT",
"WFM",
"ARIA",
"WFT",
"MO",
"PG",
"CSX",
"MGM",
"SCHW",
"NVDA",
"KEY",
"RAI",
"AMGN",
"HTZ",
"ZTS",
"USB",
"WLL",
"MAS",
"LLY",
"WPX",
"CNW",
"WMT",
"ASNA",
"LUV",
"GLW",
"BAX",
"HCA",
"NEM",
"HRTX",
"BEE",
"ETN",
"DD",
"XPO",
"HBAN",
"VLO",
"DIS",
"NRZ",
"NOV",
"MET",
"MNKD",
"MDP",
"DAL",
"XON",
"AEO",
"THC",
"AGNC",
"ESV",
"FITB",
"ESRX",
"BKD",
"GNW",
"KN",
"GIS",
"AIG",
"SYMC",
"OLN",
"NBR",
"CPN",
"TWO",
"SPLS",
"AMZN",
"UAL",
"MRVL",
"BTU",
"ODP",
"AMD",
"GLNG",
"APC",
"HL",
"PPL",
"HK",
"LNG",
"CVS",
"CYH",
"CCL",
"HD",
"AET",
"CVC",
"MNK",
"FOX",
"CRC",
"TSLA",
"UNH",
"VIAB",
"P",
"AMBA",
"SWFT",
"CNX",
"BWC",
"SRC",
"WETF",
"CNP",
"ENDP",
"JBL",
"YUM",
"MAT",
"PAH",
"FINL",
"BK",
"ARWR",
"SO",
"MTG",
"BIIB",
"CBS",
"ARNA",
"WYNN",
"TAP",
"CLR",
"LOW",
"NYMT",
"AXTA",
"BMRN",
"ILMN",
"MCD",
"NAVI",
"FNFG",
"AVP",
"ON",
"DVN",
"DHR",
"OREX",
"CFG",
"DHI",
"IBM",
"HCP",
"UA",
"KR",
"AES",
"STWD",
"BRCM",
"APA",
"STI",
"MDVN",
"EOG",
"QRVO",
"CBI",
"CL",
"ALLY",
"CALM",
"SN",
"FEYE",
"VRTX",
"KBH",
"ADXS",
"HCBK",
"OXY",
"TROX",
"NBL",
"MON",
"PM",
"MA",
"HDS",
"EMR",
"CLF",
"AVGO",
"INCY",
"M",
"PEP",
"WU",
"KERX",
"CRM",
"BCEI",
"PEG",
"NUE",
"UNP",
"SWKS",
"SPW",
"COG",
"BURL",
"MOS",
"CIM",
"CLNY",
"BBT",
"UTX",
"LVS",
"DE",
"ACN",
"DO",
"LYB",
"MPC",
"SNDK",
"AGEN",
"GGP",
"RRC",
"CNC",
"PLUG",
"JOY",
"HP",
"CA",
"LUK",
"AMTD",
"GERN",
"PSX",
"LULU",
"SYY",
"HON",
"PTEN",
"NWSA",
"MCK",
"SVU",
"DSW",
"MMM",
"CTL",
"BMR",
"PHM",
"CIE",
"BRCD",
"ATW",
"BBBY",
"BBY",
"HRB",
"ISIS",
"NWL",
"ADM",
"HOLX",
"MM",
"GS",
"AXP",
"BA",
"FAST",
"KND",
"NKTR",
"ACHN",
"REGN",
"WEN",
"CLDX",
"BHI",
"HFC",
"GNTX",
"GCA",
"CPE",
"ALL",
"ALTR",
"QEP",
"NSAM",
"ITCI",
"ALNY",
"SPF",
"INSM",
"PPHM",
"NYCB",
"NFX",
"TMO",
"TGT",
"GOOG",
"SIAL",
"GPS",
"MYGN",
"MDRX",
"TTPH",
"NI",
"IVR",
"SLH"]

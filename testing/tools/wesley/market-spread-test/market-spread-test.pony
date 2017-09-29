/*

Copyright 2017 The Wallaroo Authors.

Licensed as a Wallaroo Enterprise file under the Wallaroo Community
License (the "License"); you may not use this file except in compliance with
the License. You may obtain a copy of the License at

     https://github.com/wallaroolabs/wallaroo/blob/master/LICENSE

*/

use ".."
use "wallaroo_labs/fix"
use "collections"

actor Main
  new create(env: Env) =>
    VerifierCLI[FixOrderMessage val, MarketSpreadReceivedMessage val]
      .run_with_initialization[FixNbboMessage val, MarketData](
        env, "Market Spread", MarketSpreadResultMapper, MarketSpreadInitParser,
        MarketSpreadSentParser, MarketSpreadReceivedParser)

class MarketSpreadReceivedMessage
  let ts: U64
  let symbol: String
  let is_rejected: Bool

  new val create(ts': U64, symbol': String, is_rejected': Bool) =>
    ts = ts'
    symbol = symbol'
    is_rejected = is_rejected'

  fun string(): String iso^ =>
    ("(" + ts.string() + ", " + symbol + ": " + is_rejected.string() + ")")
      .clone()

class MarketSpreadInitParser is InitializationParser[FixNbboMessage val]
  let _messages: Array[FixNbboMessage val] = Array[FixNbboMessage val]

  fun fs(): (String|None) => None

  fun ref apply(fields: Array[String] val) ? =>
    let fix_raw = fields(0)?
    let fix_message = FixParser(fix_raw)
    match fix_message
    | let nbbo: FixNbboMessage val =>
      _messages.push(nbbo)
    end

  fun ref initialization_messages(): Array[FixNbboMessage val] =>
    _messages

class MarketSpreadSentParser is SentParser[FixOrderMessage val]
  let _messages: Array[FixOrderMessage val] = Array[FixOrderMessage val]

  fun fs(): (String|None) => None

  fun ref apply(fields: Array[String] val) ? =>
    let fix_raw = fields(0)?
    let fix_message = FixParser(fix_raw)
    match fix_message
    | let trade: FixOrderMessage val =>
      _messages.push(trade)
    end

  fun ref sent_messages(): Array[FixOrderMessage val] =>
    _messages

class MarketSpreadReceivedParser is
  ReceivedParser[MarketSpreadReceivedMessage val]

  let _messages: Array[MarketSpreadReceivedMessage val] =
    Array[MarketSpreadReceivedMessage val]

  fun ref apply(fields: Array[String] val) ? =>
    let timestamp = fields(0)?.clone().>strip().u64()?
    let symbol: String val = fields(1)?.clone().>strip().clone()
    let is_rejected = fields(10)?.bool()?
    _messages.push(MarketSpreadReceivedMessage(timestamp, consume symbol,
      is_rejected))

  fun ref received_messages(): Array[MarketSpreadReceivedMessage val] =>
    _messages

class MarketSpreadResultMapper is StatefulResultMapper[FixOrderMessage val,
  MarketSpreadReceivedMessage val, FixNbboMessage val, MarketData]

  fun init_transform(init: Array[FixNbboMessage val]):
    MarketData =>
    let state = MarketData

    for m in init.values() do
      let mid = (m.bid_px() + m.offer_px()) / 2
      if ((m.offer_px() - m.bid_px()) >= 0.05) or
        (((m.offer_px() - m.bid_px()) / mid) >= 0.05) then
        state(m.symbol()) = true
      else
        state(m.symbol()) = false
      end
    end
    state

  fun sent_transform(sent: Array[FixOrderMessage val], state: MarketData):
    CanonicalForm =>
    let tr = TradeResults

    for m in sent.values() do
      let symbol = m.symbol()
      tr(symbol) = state.is_rejected(symbol)
    end
    tr

  fun received_transform(received: Array[MarketSpreadReceivedMessage val]):
    CanonicalForm =>
    let tr = TradeResults

    for m in received.values() do
      tr(m.symbol) = m.is_rejected
    end
    tr

class TradeResults is CanonicalForm
  let results: Map[String, Bool] = Map[String, Bool]

  fun apply(s: String): Bool ? => results(s)?

  fun ref update(key: String, value: Bool) => results(key) = value

  fun compare(that: CanonicalForm): (MatchStatus val, String) =>
    match that
    | let tr: TradeResults =>
      if results.size() != tr.results.size() then
        return (ResultsDoNotMatch, "Trade results sizes do not match up")
      end
      for (symbol, is_rejected) in results.pairs() do
        try
          if is_rejected != tr(symbol)? then
            let msg = "Expected " + symbol + " rejection to be "
              + is_rejected.string() + " but it was "
              + (not is_rejected).string()
            return (ResultsDoNotMatch, msg)
          end
        else
          let msg = "Couldn't find " + symbol + " in the results."
          return (ResultsDoNotMatch, msg)
        end
      end
      (ResultsMatch, "")
    else
      (ResultsDoNotMatch, "")
    end

class MarketData
  let _data: Map[String, Bool] = Map[String, Bool]

  fun ref update(key: String, value: Bool) => _data(key) = value

  fun is_rejected(symbol: String): Bool =>
    try
      _data(symbol)?
    else
      true
    end

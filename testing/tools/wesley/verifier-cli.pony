/*

Copyright 2017 The Wallaroo Authors.

Licensed as a Wallaroo Enterprise file under the Wallaroo Community
License (the "License"); you may not use this file except in compliance with
the License. You may obtain a copy of the License at

     https://github.com/wallaroolabs/wallaroo/blob/master/LICENSE

*/

use "ini"
use "files"

primitive Usage
  fun message(command: String): String val => "Usage: ".add(command)
    .add(" SENT-FILE RECEIVED-FILE match|nomatch|TEST-INI-FILE")

primitive VerifierCLI[S: Message val, R: Message val]
  fun run(env: Env, test_name: String, result_mapper: ResultMapper[S, R],
    sent_parser: SentParser[S], received_parser: ReceivedParser[R])
  =>
    @printf[I32]("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww\n".cstring())
    @printf[I32]((" Wesley: Starting " + test_name + "\n").cstring())
    @printf[I32]("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww\n".cstring())
    match stateless_verifier_from_command_line(env, result_mapper,
      sent_parser, received_parser)
    | let verifier: StatelessVerifier[S, R] => verify(env, verifier)
    | let setup_error: SetupError =>
      env.exitcode(setup_error.exitcode())
      @printf[I32]((setup_error.message() + "\n").cstring())
    end

  fun run_with_initialization[I: Message val,
    St: Any ref](env: Env,
    test_name: String,
    result_mapper: StatefulResultMapper[S, R, I, St],
    initialization_parser: InitializationParser[I],
    sent_parser: SentParser[S],
    received_parser: ReceivedParser[R])
  =>
    @printf[I32]("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww\n".cstring())
    @printf[I32]((" Wesley: Starting " + test_name + "\n").cstring())
    @printf[I32]("wwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwwww\n".cstring())
    match stateful_verifier_from_command_line[I, St](env, result_mapper,
      initialization_parser, sent_parser, received_parser)
    | let verifier: StatefulVerifier[S, R, I, St] => verify(env, verifier)
    | let setup_error: SetupError =>
      env.exitcode(setup_error.exitcode())
      @printf[I32]((setup_error.message() + "\n").cstring())
    end

  fun stateless_verifier_from_command_line(env: Env,
    result_mapper: ResultMapper[S, R],
    sent_parser: SentParser[S],
    received_parser: ReceivedParser[R])
    : (SetupError | StatelessVerifier[S, R])
  =>
    (let prog: String, let sent_file: String, let received_file: String,
      let expectation_str: String) = try
      _parse_args(env.args)?
    else
      if env.args.size() == 1 then
        return SetupErrorNoArgs(try env.args(0)? else "???" end)
      else
        return SetupErrorWrongArgs(try env.args(0)? else "???" end)
      end
    end

    let expected_match_result: MatchStatus val = try
      match _get_expected_match_status_from_string(expectation_str)
      | let m: MatchStatus val => m
      | let ini_file_name: String =>
        let test_ini: IniMap =
          _read_expected_match_status_file(expectation_str, env.root)?
        try
          _get_expected_match_status_value(test_ini)?
        else
          return SetupErrorCouldNotFindMatchStatusInFile(ini_file_name)
        end
      else
        error
      end
    else
      return SetupErrorExpectedMatchInvalid(expectation_str)
    end

    try
      _read_text_message_file_with_parser(sent_file, sent_parser, env.root,
        env)?
    else
      return SetupErrorProblemReadingMessageFile(sent_file)
    end

    try
      _read_received_message_file_with_parser(received_file, received_parser,
        env.root, env)?
    else
      return SetupErrorProblemReadingMessageFile(received_file)
    end

    StatelessVerifier[S, R](sent_parser.sent_messages(),
      received_parser.received_messages(), result_mapper,
      expected_match_result)

  fun stateful_verifier_from_command_line[I: Message val,
    St: Any ref](env: Env,
    result_mapper: StatefulResultMapper[S, R, I, St],
    init_parser: InitializationParser[I], sent_parser: SentParser[S],
    received_parser: ReceivedParser[R])
    : (SetupError | StatefulVerifier[S, R, I, St])
  =>
    (let prog: String, let init_file: String, let sent_file: String,
      let received_file: String, let expectation_str: String) =
      try
        _parse_args_with_initialization(env.args)?
      else
        if env.args.size() == 1 then
          return SetupErrorNoArgs(try env.args(0)? else "???" end)
        else
          return SetupErrorWrongArgs(try env.args(0)? else "???" end)
        end
      end

    let expected_match_result: MatchStatus val = try
      match _get_expected_match_status_from_string(expectation_str)
      | let m: MatchStatus val => m
      | let ini_file_name: String =>
        let test_ini: IniMap =
          _read_expected_match_status_file(expectation_str, env.root)?
        try
          _get_expected_match_status_value(test_ini)?
        else
          return SetupErrorCouldNotFindMatchStatusInFile(ini_file_name)
        end
      else
        error
      end
    else
      return SetupErrorExpectedMatchInvalid(expectation_str)
    end

    try
      _read_text_message_file_with_parser(init_file, init_parser, env.root,
        env)?
    else
      return SetupErrorProblemReadingMessageFile(init_file)
    end

    try
      _read_text_message_file_with_parser(sent_file, sent_parser, env.root,
        env)?
    else
      return SetupErrorProblemReadingMessageFile(sent_file)
    end

    try
      _read_received_message_file_with_parser(received_file, received_parser,
       env.root, env)?
    else
      return SetupErrorProblemReadingMessageFile(received_file)
    end

    StatefulVerifier[S, R, I, St](
      init_parser.initialization_messages(),
      sent_parser.sent_messages(),
      received_parser.received_messages(), result_mapper,
      expected_match_result)

  fun _parse_args(args: Array[String] val)
    : (String, String, String, String) ?
  =>
    if args.size() == 4 then
       (args(0)?, args(1)?, args(2)?, args(3)?)
    else
      error
    end

 fun _parse_args_with_initialization(args: Array[String] val)
   : (String, String, String, String, String) ?
  =>
    if args.size() == 5 then
       (args(0)?, args(1)?, args(2)?, args(3)?, args(4)?)
    else
      error
    end

  fun _get_expected_match_status_from_string(
    expected_match_result_str: String): (MatchStatus val | String) =>
    match expected_match_result_str
    | "match" => ResultsMatch
    | "nomatch" => ResultsDoNotMatch
    else
      expected_match_result_str
    end

  fun _read_expected_match_status_file(file_name: String,
    root: (AmbientAuth | None)): IniMap ? =>
    var test_ini: IniMap = IniMap
    let caps = recover val FileCaps.>set(FileRead).>set(FileStat) end
    with file = OpenFile(FilePath(root as AmbientAuth, file_name, caps)?)
      as File do
      test_ini = IniParse(file.lines())?
    end
    test_ini

  fun _get_expected_match_status_value(test_ini: IniMap): MatchStatus val ? =>
    let test_config = test_ini("test_config")?
    let expected_result = test_config("expected_result")?
    match expected_result
    | "match" => ResultsMatch
    | "nomatch" => ResultsDoNotMatch
    else
      error
    end

  fun _read_text_message_file_with_parser(file_name: String,
    parser: TextMessageFileParser, root: (AmbientAuth | None),
    env: Env) ?
  =>
    let caps = recover val FileCaps.>set(FileRead).>set(FileStat) end
    with file = OpenFile(FilePath(root as AmbientAuth, file_name, caps)?)
      as File do
      TextMessageFileReader(file.read_string(file.size()), parser, env)?
    else
      error
    end

  fun _read_received_message_file_with_parser(file_name: String,
    parser: MessageFileParser, root: (AmbientAuth | None), env: Env) ?
  =>
    let caps = recover val FileCaps.>set(FileRead).>set(FileStat) end
    with file = OpenFile(FilePath(root as AmbientAuth, file_name, caps)?)
      as File do
      ReceivedMessageFileReader(file.read(file.size()), parser, env)?
    else
      error
    end

  fun verify(env:Env, verifier: Verifier ref) =>
    let pass_fail = verifier.test()
    @printf[I32]((pass_fail.exitmessage() + "\n").cstring())
    env.exitcode(pass_fail.exitcode())

interface SetupError
  fun exitcode(): I32 => 0
  fun message(): String => ""

class SetupErrorNoArgs is SetupError
  let _message: String val
  new create(command: String) =>
    _message = Usage.message(command)
  fun exitcode(): I32 => 0
  fun message(): String => _message

class SetupErrorWrongArgs is SetupError
  let _message: String val
  new create(command: String) =>
    _message = Usage.message(command)
  fun exitcode(): I32 => 90
  fun message(): String => _message

class SetupErrorExpectedMatchInvalid
  let _message: String
  new create(expected_match: String) =>
    _message = "Error: Expected match was '".add(expected_match)
      .add("', must be one of: match nomatch TEST-INI-FILE")
  fun exitcode(): I32 => 91
  fun message(): String => _message

class SetupErrorCouldNotFindMatchStatusInFile
  let _message: String val
  new create(file_name: String) =>
    _message = "Error: Could not find section '[test_config]' with property"
      + "'expected_result' in file '".add(file_name).add("'.")
  fun exitcode(): I32 => 92
  fun message(): String => _message

class SetupErrorProblemReadingMessageFile
  let _message: String val
  new create(file_name: String) =>
    _message = "Error: Problem reading MessageFile file '".add(file_name)
      .add("'.")
  fun exitcode(): I32 => 93
  fun message(): String => _message

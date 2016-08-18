use "ponytest"

actor TestMain is TestList
  new create(env: Env) => PonyTest(env, this)

  new make() => None

  fun tag tests(test: PonyTest) =>
    test(_TestTextOutputEncoder)

class iso _TestTextOutputEncoder is UnitTest
  """
  Verify that the giles sender log encoder is encoding individual lines as
  expected
  """
  fun name(): String => "giles/sender:TextOutputEncoder"

  fun apply(h: TestHelper) =>
    let hello_world = TextOutputEncoder(("Hello World", 95939399))
    h.assert_eq[String](hello_world,"95939399, Hello World")

    let hello_walken= TextOutputEncoder(("Hello, World: The Christopher Walken Story",
    23123213))
    h.assert_eq[String](hello_walken,
    "23123213, Hello, World: The Christopher Walken Story")

    let one = TextOutputEncoder(("1", 1))
    h.assert_eq[String](one, "1, 1")

    let ten = TextOutputEncoder(("10", 2))
    h.assert_eq[String](ten, "2, 10")

    let one_hundred = TextOutputEncoder(("100", 3))
    h.assert_eq[String](one_hundred, "3, 100")

    let one_thousand = TextOutputEncoder(("1000", 4))
    h.assert_eq[String](one_thousand, "4, 1000")

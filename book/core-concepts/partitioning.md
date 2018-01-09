# Partitioning

If all of the application state exists in one state object then only one computation at a time can access that state object. In order to leverage concurrency, that state needs to be divided into multiple distinct state objects. Wallaroo can then automatically distribute these objects in a way that allows them to be accessed by computations in parallel.

For example, in an application that keeps track of stock prices, the application state might be a dictionary where the stock symbol is used to look up the price of the stock.

{% codetabs name="Python", type="py" -%}
class Stock(object):
    def __init__(self, symbol, price):
        self.symbol = symbol
        self.price = price


class Stocks(object):
    def __init__(self):
        self.stocks = {}

    def set(self, symbol, price):
        stock = self.stocks[symbol]
        stock.price = price
{%- language name="Go", type="go" -%}
type Stock struct {
  Symbol string
  Price float64
}

type Stocks struct {
  Stocks map[string]Stock
}

func (s *Stocks) Set(symbol string, price float64) {
  stock := s[symbol]
  stock.Price = price
}
{%- endcodetabs %}

If a message came into the system with a new stock price, the computation would take that message, get the symbol and the price, and use them to update the state.

{% codetabs name="Python", type="py" -%}
@wallaroo.state_computation("update stock")
def update_stock(stock, state):
    symbol = stock.symbol
    price = stock.price

    state.set(symbol, price)
    return (None, True)
{%- language name="Go", type="go" -%}
type UpdateStock struct {}

func (us *UpdateStock) Compute(data interface{}, state interface{}) (interface{}, bool) {
    stock := data.(*Stock)
    stocks := state.(*Stocks)

    stocks.Set(stock.Symbol, stock.Price)
    return nil, true
}
{%- endcodetabs %}


However, only one computation may access the state at a time, so in this cases messages are handled one at a time.

If we could break the state into pieces and tell Wallaroo about those pieces then we could process many messages concurrently. In the example, each stock could be broken out into it's own piece of state. This is possible because in the model the price of each stock is independent of the price of any other stock, so modifying one has no effect on any of the others.

## State Partitioning

Wallaroo supports parallel execution by way of _state partitioning_. The state is broken up into distinct parts, and Wallaroo manages access to each part so that they can be accessed in parallel.
To do this, a _partition function_ is used to determine which _state part_ a particular data should be applied to. Once the _part_ is determined, the data and the associated _state part_ are given to a Computation to perform the update logic.

### Partitioned State

In order to take advantage of state partitioning, state objects need to be broken down. In the stock example there is already a class that represents an individual stock, so it can be used as the partitioned state.

{% codetabs name="Python", type="py" -%}
class Stock(object):
    def __init__(self, symbol, price):
        self.symbol = symbol
        self.price = price
{%- language name="Go", type="go" -%}
type Stock struct {
  Symbol string
  Price float64
}
{%- endcodetabs %}

Since the computation only has one stock in its state now, there is no need to do a dictionary look up. Instead, the computation can update the particular Stock's state right away.

{% codetabs name="Python", type="py" -%}
@wallaroo.state_computation(name="update stock")
def update_stock(stock, state):
    state.symbol = stock.symbol
    state.price = stock.price

    return (None, True)
{%- language name="Go", type="go" -%}
type UpdateStock struct {}

func (us *UpdateStock) Compute(data interface{}, state interface{}) (interface{}, bool) {
    stock := data.(*Stock)
    state := state.(*Stock)

    state.Symbol = stock.Symbol
    state.Price = stock.Price

    return nil, true
{%- endcodetabs %}

### Partition Key

Currently, the partition keys for a particular partition need to be defined along with the application. The specific details of keys vary between the different language APIs, but they are typically an object of some type that can support comparison and hashing. In the stock example, the partition key would be based on the symbol name (a string). All of the expected stock symbols are passed to the application setup code.

### Partition Function

The partition function takes in message data and returns a partition key. In the example, the message symbol would be extracted from the message data and returned as the key.

{% codetabs name="Python", type="py" -%}
@wallaroo.partition
def partition(data):
    return data.symbol
{%- language name="Go", type="go" -%}
func symbolToKey(symbol string) uint64 {
    return uint64(binary.BigEndian.Uint32([]byte(fmt.Sprintf("%4s", symbol))))
}

type SymbolPartitionFunction struct {
}

func (spf *SymbolPartitionFunction) Partition(data interface{}) uint64 {
    symbol := data.(SymbolMessage).GetSymbol()
    return symbolToKey(symbol)
}
{%- endcodetabs %}

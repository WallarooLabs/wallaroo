# Wallaroo Python Examples

In this section you will find the complete examples from the [Wallaroo Python](https://docs.wallaroolabs.com/book/python/intro.html) section, as well as some additional examples. Each example includes a README describing its purpose and how to set it up and run it.

To get set up for running examples, if you haven't already, refer to [Building a Python application](/book/python/building.md).

## Examples by Category

### Simple Stateless Applications

- [reverse](reverse/): a string reversing stream application.
- [celsius](celsius/): a Celsius-to-Fahrenheit stream application.
- [celsius-kafka](celsius-kafka/): A Celsius-to-Fahrenheit stream application using a Kafka source and a Kafka sink (instead of a TCP source and a TCP sink).

### Simple Stateful Applications

- [alphabet](alphabet/): a vote counting stream application.

### Partitioned Stateful Applications

- [alphabet_partitioned](alphabet_partitioned/): a vote counting stream application using partitioning.
- [market_spread](market_spread/): a stream application that keeps a state for market data and checks trade orders against it in real time. This application uses state, partitioning, and two pipelines, each with its own source.


# Run a Wallaroo Application

In this section, we're going to show you how to quickly get a Wallaroo application up and running. We'll be using an example application that converts a stream of Celsius values to Fahrenheit.

We'll be sending our Celsius values into Wallaroo as a stream of bytes over TCP. The outputs of our application will be converted to a stream of bytes and sent over TCP to a data receiver.

## Set up Environment for Wallaroo

Create a directory called `~/wallaroo-tutorial` and navigate there by running

```
mkdir ~/wallaroo-tutorial
cd ~/wallaroo-tutorial
```

This will be our base directory in what follows. If you haven't already
cloned this repo, do so by running:

```
git clone https://github.com/sendence/wallaroo-documentation
```

Note: You need to login to GitHub for credentials

This will create a subdirectory called `wallaroo-documentation`.

If you haven't already, you now need to set up your environment for Wallaroo. Follow the instructions [here](setup.md).

## Start the Metrics UI

To start the Metrics UI run:

```bash
docker run -d --name mui -p 0.0.0.0:4000:4000 -p 0.0.0.0:5001:5001 \ 
sendence/wallaroo-metrics-ui
```

You can verify it started up correctly by visiting [http://localhost:4000](http://localhost:4000). 

If you need to restart the UI, run:

```bash
docker restart mui
```

When it's time to stop the UI, run:

```bash
docker stop mui
```

## Clone the Wallaroo repo

There are two support applications we are going to need to compile that are kept in the [Wallaroo Github repository](https://github.com/sendence/wallaroo).

Open a new terminal and run the following to clone the repo:

```bash
cd ~/wallaroo-tutorial
git clone https://github.com/sendence/wallaroo
git checkout 3af6c610ca4c4c07c75eba68b24447d2b65950c2
```

Later in the process we will build each of the applications:

- Giles Receiver
- Giles Sender

## Run Giles Receiver

We need to set up a data receiver where we can send the output stream from our app. Wallaroo ships with a tool called `Giles Receiver` designed to capture TCP output.

```bash
cd ~/wallaroo-tutorial/wallaroo/giles/receiver
stable env ponyc
```

This will create a binary called `receiver`

You will now be able to start the `receiver` with the following command:

```bash
./receiver -l 127.0.0.1:5555
```

You should see the `Listening for data` that indicates that Giles receiver is running.

## Compile the Celsius Converter App

The example application we'll be running can be found [here](https://github.com/Sendence/wallaroo-documentation/blob/master/examples/celsius/celsius.pony). From the `~/wallaroo-tutorial` directory, run the following command:

```bash
cd ~/wallaroo-tutorial/wallaroo-documentation/examples/celsius
```

Now compile the Celsius Converter app:

```bash
stable fetch && stable env ponyc
```

This will create a binary called `celsius`.

## Run the Celsius Converter App

Now that we have our Celsius Converter application compiled, and the metrics UI and something it can send output to up and running, we can run the application itself by executing the following command from our original terminal:

```bash
./celsius -i 127.0.0.1:7000 -o 127.0.0.1:5555 -m 127.0.0.1:5001 \
-c 127.0.0.1:6000 -d 127.0.0.1:6001
```

This tells Wallaroo that it should listen on port 7000 for incoming data, write outgoing data to port 5555, and send metrics data to port 5001.

## Let's Get Some Data: Running Giles Sender

Giles Sender is used to mimic the behavior of an incoming data source.

Open a new terminal and run the following to compile the sender:

```bash
cd ~/wallaroo-tutorial/wallaroo/giles/sender
stable env ponyc
```

This will create a binary called `sender`

You will now be able to start the `sender` with the following command:

```bash
./sender -b 127.0.0.1:7000 -m 10000000 -y -s 300 \
-f ~/wallaroo-tutorial/wallaroo-documentation/examples/celsius/generator/celsius.msg \
-r -w -g 8
```

If the sender is working correctly, you should see `Connected` printed to the screen. If you see that, you can be assured that we are now sending data into our example application.

## Check Out Some Metrics

Once the sender has successfully connected, if you [visit the Metrics UI](http://localhost:4000) you should be able to see updates as our Celsius Converter application processes incoming data.


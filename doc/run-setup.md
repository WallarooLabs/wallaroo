The ordering of items is important. Start them up in the order listed.

DOUBLE DIVIDE

Monitoring Hub:
```
iex --sname monitoring_hub -S mix phoenix.server
```

Metrics Receiver:
```
apps/double-divide/double-divide --run-sink -r -l 127.0.0.1:9000 -m 127.0.0.1:5001 -e 1 -a double-divide --ponythreads 1
```

Giles receiver:
```
giles/receiver/receiver -l 127.0.0.1:8000 --ponythreads 1
```

Buffy:
```
apps/double-divide/double-divide -l -w 0 -c 127.0.0.1:6000 -d 127.0.0.1:6001 -r 127.0.0.1:7000 -k 127.0.0.1:8000 -n leader -p 127.0.0.1:11000 -m 127.0.0.1:9000 --ponythreads 3
```

Giles sender:
```
giles/sender/sender -b 127.0.0.1:7000 -m 1000000 --ponythreads 1 -s 500
```

MARKET SPREAD

Monitoring Hub:
```
iex --sname monitoring_hub -S mix phoenix.server
```

Metrics Receiver:
```
apps/market-spread/market-spread --run-sink -r -l 127.0.0.1:9000 -m 127.0.0.1:5001 -e 1 -a market-spread --ponythreads 1
```

UI Report Sink node:
```
apps/market-spread/market-spread --run-sink -l 127.0.0.1:8001 -t 127.0.0.1:5555 -p 127.0.0.1:11000 -n reports --ponythreads 1
```

Giles receiver:
```
giles/receiver/receiver -l 127.0.0.1:8000 --ponythreads 1
```

Buffy:
```
apps/market-spread/market-spread -l -w 0 -c 127.0.0.1:6000 -d 127.0.0.1:6001 -r 127.0.0.1:7000,127.0.0.1:7001 -k 127.0.0.1:8000,127.0.0.1:8001,127.0.0.1:8002 -n leader -p 127.0.0.1:11000 -m 127.0.0.1:9000 --ponythreads 3
```

Giles sender:
```
giles/sender/sender -b 127.0.0.1:7000 -m 1000000 -f ./demos/marketspread/trades.msg -r --ponythreads 1 -s 500

giles/sender/sender -b 127.0.0.1:7001 -m 1000000 -f ./demos/marketspread/nbbo.msg -r --ponythreads 1 -s 500
```

WORD COUNT

Giles receiver:
```
giles/receiver/receiver -l 127.0.0.1:8000 --ponythreads 1
```

Buffy:
```
apps/word-count/word-count -l -w 0 -c 127.0.0.1:6000 -d 127.0.0.1:6001 -r 127.0.0.1:7000 -k 127.0.0.1:8000 -n leader -p 127.0.0.1:11000 -m 127.0.0.1:9000 --ponythreads 3
```

Giles sender:
```
giles/sender/sender -b 127.0.0.1:7000 -f ./apps/word-count/encb11.txt,./apps/word-count/encguten.txt,./apps/word-count/holmes.txt,./apps/word-count/monte-cristo.txt,./apps/word-count/stuff.txt -r --ponythreads 1 -m 1000000 -s 500 
```

TOP

```
top | grep 'buffy\|double\|word-count\|market-spread'
```

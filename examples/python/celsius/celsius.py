# Copyright 2017 The Wallaroo Authors.
#
#  Licensed under the Apache License, Version 2.0 (the "License");
#  you may not use this file except in compliance with the License.
#  You may obtain a copy of the License at
#
#      http://www.apache.org/licenses/LICENSE-2.0
#
#  Unless required by applicable law or agreed to in writing, software
#  distributed under the License is distributed on an "AS IS" BASIS,
#  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
#  implied. See the License for the specific language governing
#  permissions and limitations under the License.


import struct

import wallaroo


def application_setup(args):
    in_host, in_port = wallaroo.tcp_parse_input_addrs(args)[0]
    out_host, out_port = wallaroo.tcp_parse_output_addrs(args)[0]

    ab = wallaroo.ApplicationBuilder("Celsius to Fahrenheit")
    ab.new_pipeline("Celsius Conversion",
                    wallaroo.TCPSourceConfig(in_host, in_port, decoder))
    ab.to(multiply)
    ab.to(add)
    ab.to_sink(wallaroo.TCPSinkConfig(out_host, out_port, encoder))
    return ab.build()


@wallaroo.decoder(header_length=4, length_fmt=">I")
def decoder(bs):
    return struct.unpack(">f", bs)[0]


@wallaroo.computation(name="multiply by 1.8")
def multiply(data):
    return data * 1.8


@wallaroo.computation(name="add 32")
def add(data):
    return data + 32


@wallaroo.encoder
def encoder(data):
    return "%.6f\n" % (data)

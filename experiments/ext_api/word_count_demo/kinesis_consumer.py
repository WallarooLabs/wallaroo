from __future__ import print_function
import sys

from boto import kinesis
from text_documents import TextStream, parse_text_stream_addr
import time

shard_id = 'shardId-000000000000'
conn = kinesis.connect_to_region(region_name = "us-east-1")
shard_it = conn.get_shard_iterator('bill_of_rights', shard_id, "LATEST")["ShardIterator"]

text_stream_addr = parse_text_stream_addr(sys.argv)
extension = TextStream(*text_stream_addr).extension()

while True:
    message = conn.get_records(shard_it, limit=2)
    for record in message["Records"]:
        extension.write(record["Data"])
    shard_it = message["NextShardIterator"]
    time.sleep(0.2)

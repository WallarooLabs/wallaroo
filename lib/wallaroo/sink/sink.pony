/*

Copyright 2017 The Wallaroo Authors.

 Licensed under the Apache License, Version 2.0 (the "License");
 you may not use this file except in compliance with the License.
 You may obtain a copy of the License at

     http://www.apache.org/licenses/LICENSE-2.0

 Unless required by applicable law or agreed to in writing, software
 distributed under the License is distributed on an "AS IS" BASIS,
 WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or
 implied. See the License for the specific language governing
 permissions and limitations under the License.

*/

use "wallaroo/core"
use "wallaroo/metrics"
use "wallaroo/routing"
use "wallaroo/topology"

type Sink is (Consumer & DisposableActor)

interface val SinkConfig[Out: Any val]
  fun apply(): SinkBuilder

interface val SinkBuilder
  fun apply(reporter: MetricsReporter iso): Sink

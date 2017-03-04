import 'dart:async';

import 'common.dart';
import 'serialization.dart';
import 'session.dart';
import 'metadata.dart';
import 'messages.dart';
import 'produce_api.dart';

abstract class KProducer<K, V> {
  factory KProducer(Serializer<K> keySerializer, Serializer<V> valueSerializer,
      KSession session) {
    return new _ProducerImpl(keySerializer, valueSerializer, session: session);
  }

  Future<ProduceResult> send(ProducerRecord<K, V> record);
}

class ProducerRecord<K, V> {
  final String topic;
  final int partition;
  final K key;
  final V value;

  ProducerRecord(this.topic, this.partition, this.key, this.value);
}

class ProduceResult {
  final TopicPartition topicPartition;
  final int offset;

  ProduceResult(this.topicPartition, this.offset);
}

class _ProducerImpl<K, V> implements KProducer<K, V> {
  final KSession session;
  final Serializer<K> keySerializer;
  final Serializer<V> valueSerializer;

  _ProducerImpl(this.keySerializer, this.valueSerializer, {KSession session})
      : session = (session is KSession) ? session : KAFKA_DEFAULT_SESSION;

  @override
  Future<ProduceResult> send(ProducerRecord<K, V> record) async {
    var key = keySerializer.serialize(record.key);
    var value = valueSerializer.serialize(record.value);
    var message = new Message(value, key: key);
    var messages = {
      record.topic: {
        record.partition: [message]
      }
    };
    var req = new ProduceRequestV0(1, 1000, messages);
    var metadata = new KMetadata(session: session);
    var meta = await metadata.fetchTopics([record.topic]);
    var leaderId = meta.first.partitions
        .firstWhere((_) => _.partitionId == record.partition)
        .leader;
    var brokers = await metadata.listBrokers();
    var broker = brokers.firstWhere((_) => _.id == leaderId);
    var result = await session.send(req, broker.host, broker.port);

    return new Future.value(new ProduceResult(
        new TopicPartition(record.topic, record.partition),
        result.results.first.offset));
  }
}
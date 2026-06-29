package com.example.shinyswarm.config;

import java.util.ArrayList;
import java.util.List;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;
import org.springframework.kafka.core.KafkaAdmin;

@Configuration
public class KafkaConfig {

    // Each app type gets its own input topic so backends consume only their
    // own traffic. 3 partitions per topic allows up to 3 backend replicas to
    // process in parallel (one partition per replica), mirroring the REST
    // architecture's replicas=3 for a fair comparison.
    private static final int INPUT_PARTITIONS = 3;
    private static final int OUTPUT_PARTITIONS = 3;
    private static final int REPLICATION = 1;

    /**
     * Per-app input topics + shared output topic, created automatically on
     * startup. Wrapped in KafkaAdmin.NewTopics so KafkaAdmin picks up the whole
     * set from a single bean.
     */
    @Bean
    public KafkaAdmin.NewTopics shinyswarmTopics() {
        List<NewTopic> topics = new ArrayList<>();
        for (String name : KafkaTopics.allInputTopics()) {
            topics.add(TopicBuilder.name(name)
                    .partitions(INPUT_PARTITIONS)
                    .replicas(REPLICATION)
                    .build());
        }
        // Shared output topic: keyed by sessionId; carries results + SYSTEM messages.
        topics.add(TopicBuilder.name(KafkaTopics.OUTPUT)
                .partitions(OUTPUT_PARTITIONS)
                .replicas(REPLICATION)
                .build());
        return new KafkaAdmin.NewTopics(topics.toArray(new NewTopic[0]));
    }
}
package com.example.shinyswarm.config;

import org.apache.kafka.clients.admin.NewTopic;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.kafka.config.TopicBuilder;

@Configuration
public class KafkaConfig {

    // Automatically create the 'input' topic if it doesn't exist
    @Bean
    public NewTopic inputTopic() {
        return TopicBuilder.name("input")
                .partitions(1)
                .replicas(1)
                .build();
    }
}
package com.example.shinyswarm.state;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

@Service
public class SessionStateMonitor {

    // Thread-safe map to store the latest JSON state for each Session ID (or User ID)
    // Key: SessionID (e.g., "df56ae5e..."), Value: JSON String
    private final Map<String, String> sessionStates = new ConcurrentHashMap<>();

    // Listen to the 'output' topic (where R sends results)
    @KafkaListener(topics = "output", groupId = "spring-backend-state-monitor")
    public void listen(ConsumerRecord<String, String> record) {
        if (record.key() != null && record.value() != null) {
            // Update the cache with the latest state
            sessionStates.put(record.key(), record.value());
            // Optional: Print to verify it's working
            // System.out.println("MONITOR: Updated state for " + record.key());
        }
    }

    public String getLatestState(String key) {
        return sessionStates.get(key);
    }
}
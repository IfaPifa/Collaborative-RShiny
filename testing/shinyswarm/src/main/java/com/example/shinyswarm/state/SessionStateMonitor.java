package com.example.shinyswarm.state;

import java.util.Map;
import java.util.concurrent.ConcurrentHashMap;

import org.apache.kafka.clients.consumer.ConsumerRecord;
import org.springframework.kafka.annotation.KafkaListener;
import org.springframework.stereotype.Service;

import com.fasterxml.jackson.databind.JsonNode;
import com.fasterxml.jackson.databind.ObjectMapper;
import com.fasterxml.jackson.databind.node.ArrayNode;
import com.fasterxml.jackson.databind.node.ObjectNode;

@Service
public class SessionStateMonitor {

    private final Map<String, String> sessionStates = new ConcurrentHashMap<>();
    private final ObjectMapper objectMapper = new ObjectMapper();

    @KafkaListener(topics = "output", groupId = "spring-backend-state-monitor")
    public void listen(ConsumerRecord<String, String> record) {
        String key = record.key();
        String value = record.value();

        if (key == null || value == null) return;

        try {
            // Parse the incoming Kafka message
            JsonNode jsonNode = objectMapper.readTree(value);
            String type = jsonNode.has("type") ? jsonNode.get("type").asText() : "UNKNOWN";

            if ("PROGRESS".equals(type)) {
                // Do nothing. We don't want to save a transient progress bar state to Postgres.
                return;
                
            } else if ("DELTA".equals(type)) {
                // 1. Fetch the existing map state (or create a blank one)
                String existingStateStr = sessionStates.getOrDefault(key, "{\"type\":\"RESTORE_STATE\", \"sensors\":[]}");
                ObjectNode existingState = (ObjectNode) objectMapper.readTree(existingStateStr);
                ArrayNode sensors = (ArrayNode) existingState.get("sensors");
                
                // 2. Extract the new pin data
                ObjectNode newSensor = objectMapper.createObjectNode();
                newSensor.put("lat", jsonNode.get("lat").asDouble());
                newSensor.put("lng", jsonNode.get("lng").asDouble());
                newSensor.put("sensor_type", jsonNode.get("sensor_type").asText());
                newSensor.put("sender", jsonNode.get("sender").asText());
                
                // 3. Append and update the cache
                sensors.add(newSensor);
                sessionStates.put(key, objectMapper.writeValueAsString(existingState));
                
            } else {
                // For STATE_UPDATE (Analytics), RESULT (Monte Carlo), or legacy apps
                // We safely overwrite the entire state.
                sessionStates.put(key, value);
            }

        } catch (Exception e) {
            // Fallback for older apps that might not have a "type" field
            sessionStates.put(key, value);
        }
    }

    public String getLatestState(String key) {
        return sessionStates.get(key);
    }
}
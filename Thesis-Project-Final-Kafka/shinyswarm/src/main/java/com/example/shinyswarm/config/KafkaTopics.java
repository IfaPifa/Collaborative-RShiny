package com.example.shinyswarm.config;

import java.util.List;
import java.util.Map;

/**
 * Central definition of per-app Kafka input topics.
 *
 * Each Shiny app type has its own input topic so backend workers subscribe
 * only to their own traffic instead of reading the shared "input" topic and
 * discarding messages addressed to other apps. The legacy single-topic design
 * forced every backend to read every message (N-way fan-out on one partition),
 * which capped throughput and prevented horizontal scaling.
 *
 * Routing is resolved two ways:
 *   - by appName field in the state JSON (normal POST path), via {@link #forAppName}
 *   - by the session's appId (restore/replay path where JSON may omit appName),
 *     via {@link #forAppId}
 *
 * The "output" topic stays shared: it is keyed by sessionId and carries both
 * per-session results and SYSTEM/role-update messages, consumed by the Spring
 * SessionStateMonitor and by every frontend filtering on its own key.
 */
public final class KafkaTopics {

    private KafkaTopics() {}

    public static final String OUTPUT = "output";

    /** Fallback topic for messages whose app cannot be resolved. */
    public static final String INPUT_FALLBACK = "input";

    // appName (from state JSON) -> input topic
    private static final Map<String, String> BY_APP_NAME = Map.of(
        "Calculator",     "input.calculator",
        "Analytics",      "input.analytics",
        "Advanced",       "input.advanced",
        "DataExchange",   "input.dataexchange",
        "MonteCarlo",     "input.montecarlo",
        "Geospatial",     "input.geospatial",
        "ClimateAnomaly", "input.climateanomaly",
        "MLTrainer",      "input.mltrainer"
    );

    // appId (DataInitializer insertion order) -> input topic
    private static final Map<Long, String> BY_APP_ID = Map.of(
        1L, "input.calculator",
        2L, "input.analytics",
        3L, "input.advanced",
        4L, "input.dataexchange",
        5L, "input.montecarlo",
        6L, "input.geospatial",
        7L, "input.climateanomaly",
        8L, "input.mltrainer"
    );

    /** All declared per-app input topics (for topic creation). */
    public static List<String> allInputTopics() {
        return List.copyOf(BY_APP_ID.values());
    }

    /** Resolve topic from the appName carried in the state JSON. */
    public static String forAppName(String appName) {
        if (appName == null) return null;
        return BY_APP_NAME.get(appName);
    }

    /** Resolve topic from the session's appId (authoritative; used for restore/replay). */
    public static String forAppId(Long appId) {
        if (appId == null) return null;
        return BY_APP_ID.get(appId);
    }
}

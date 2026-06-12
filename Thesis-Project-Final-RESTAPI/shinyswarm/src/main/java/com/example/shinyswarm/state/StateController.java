package com.example.shinyswarm.state;

import java.io.BufferedReader;
import java.io.FileReader;
import java.nio.file.Files;
import java.nio.file.Path;
import java.nio.file.Paths;
import java.security.Principal;
import java.util.ArrayList;
import java.util.LinkedHashMap;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RequestParam;
import org.springframework.web.bind.annotation.RestController;

import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.app.ShinyAppRepository;
import com.example.shinyswarm.session.CollaborationSession;
import com.example.shinyswarm.session.CollaborationSessionRepository;
import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

record SaveStateRequest(Long appId, String name, String sessionId) {}
record SavedStateResponse(Long id, String appName, String name, String stateData, String createdAt, String savedBy) {}

@RestController
@RequestMapping("/api/states")
@CrossOrigin(origins = "http://localhost:4200") 
public class StateController {

    private final SavedStateRepository savedStateRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final CollaborationSessionRepository sessionRepository;
    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper; 
    private final SessionStateMonitor sessionStateMonitor; 

    public StateController(SavedStateRepository savedStateRepository, 
                           UserRepository userRepository, 
                           ShinyAppRepository shinyAppRepository,
                           CollaborationSessionRepository sessionRepository,
                           StringRedisTemplate redisTemplate,
                           ObjectMapper objectMapper,
                           SessionStateMonitor sessionStateMonitor) {
        this.savedStateRepository = savedStateRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.sessionRepository = sessionRepository;
        this.redisTemplate = redisTemplate;
        this.objectMapper = objectMapper;
        this.sessionStateMonitor = sessionStateMonitor;
    }

    @PostMapping
    public ResponseEntity<?> saveState(@RequestBody SaveStateRequest request, Principal principal) {
        String username = principal.getName();
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));

        ShinyApp app = shinyAppRepository.findById(request.appId())
                .orElseThrow(() -> new RuntimeException("App not found"));

        String cacheKey = (request.sessionId() != null && !request.sessionId().isEmpty()) 
                          ? request.sessionId() 
                          : username;
                          
        // The Proper Fix
        String latestRealState = sessionStateMonitor.getLatestState(cacheKey);

        if (latestRealState == null && cacheKey.equals(username)) {
            // Solo Redis key is solo-{appId}-{username}, matching the iframe sessionId
            latestRealState = sessionStateMonitor.getLatestState("solo-" + request.appId() + "-" + username);
        }

        if (latestRealState == null) {
            return ResponseEntity.badRequest().body("No data generated yet. Run the app analysis first before saving.");
        }

        // Enrich Climate Anomaly checkpoints with the processed CSV data
        latestRealState = enrichClimateCheckpoint(latestRealState);

        // Store sessionId so other participants can see and restore this checkpoint.
        // Solo-mode keys (e.g. "solo-1-alice") are not real session UUIDs — exclude them.
        String sessionId = (request.sessionId() != null 
                           && !request.sessionId().isEmpty()
                           && !request.sessionId().startsWith("solo-")) 
                           ? request.sessionId() : null;
        SavedState newState = new SavedState(request.name(), latestRealState, user, app, sessionId);
        savedStateRepository.save(newState);

        return ResponseEntity.ok("State saved successfully");
    }

    @GetMapping
    public List<SavedStateResponse> getMyStates(
            @RequestParam(required = false) String sessionId,
            Principal principal) {
        String username = principal.getName();
        List<SavedState> states;

        if (sessionId != null && !sessionId.isEmpty()) {
            // In a collaboration session: show all checkpoints saved by any participant
            // Verify the caller is actually a participant
            CollaborationSession session = sessionRepository.findById(sessionId).orElse(null);
            if (session == null || session.getParticipants().stream()
                    .noneMatch(p -> p.getUser().getUsername().equals(username))) {
                states = List.of();
            } else {
                states = savedStateRepository.findBySessionIdOrderByCreatedAtDesc(sessionId);
            }
        } else {
            // Solo mode: show only the user's own saves
            states = savedStateRepository.findByUser_UsernameOrderByCreatedAtDesc(username);
        }

        return states.stream()
                .map(state -> new SavedStateResponse(
                        state.getId(),
                        state.getShinyApp().getName(),
                        state.getName(),
                        state.getStateData(),
                        state.getCreatedAt().toString(),
                        state.getUser().getUsername()
                ))
                .collect(Collectors.toList());
    }

    @PostMapping("/{id}/restore")
    public ResponseEntity<?> restoreState(
            @PathVariable Long id, 
            @RequestParam(required = false) String sessionId, 
            Principal principal) {

        SavedState state = savedStateRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("State not found"));
        
        String username = principal.getName();
        boolean isOwner = state.getUser().getUsername().equals(username);
        boolean isSessionParticipant = false;

        // Allow restore if the checkpoint belongs to a session the user participates in
        if (!isOwner && state.getSessionId() != null) {
            CollaborationSession session = sessionRepository.findById(state.getSessionId()).orElse(null);
            if (session != null) {
                isSessionParticipant = session.getParticipants().stream()
                        .anyMatch(p -> p.getUser().getUsername().equals(username));
            }
        }

        if (!isOwner && !isSessionParticipant) {
            return ResponseEntity.status(403).body("You do not have access to this checkpoint");
        }

        try {
            Map<String, Object> payload = objectMapper.readValue(state.getStateData(), Map.class);

            // Write embedded Climate Anomaly data back to the shared volume
            restoreClimateFile(payload);

            payload.put("sender", "System Restore");
            // Use seconds (not millis) to match R's as.numeric(Sys.time())
            payload.put("timestamp", System.currentTimeMillis() / 1000.0);
            
            String redisPayload = objectMapper.writeValueAsString(payload);

            String cacheKey = (sessionId != null && !sessionId.isEmpty()) ? sessionId : principal.getName();
            
            // Bridge solo restores: Angular sets iframe sessionId to "solo-{appId}-{username}"
            // so the Shiny app polls session_state:solo-{appId}-{username}
            if (cacheKey.equals(principal.getName())) {
                cacheKey = "solo-" + state.getShinyApp().getId() + "-" + principal.getName();
            }

            redisTemplate.opsForValue().set("session_state:" + cacheKey, redisPayload);
            
            return ResponseEntity.ok("State restored");

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to parse state data");
        }
    }

    @SuppressWarnings("unchecked")
    private String enrichClimateCheckpoint(String stateData) {
        try {
            Map<String, Object> payload = objectMapper.readValue(stateData, Map.class);
            String action = (String) payload.get("action");
            String file = (String) payload.get("file");

            if (!"CLIMATE_READY".equals(action) || file == null || file.isEmpty()) {
                return stateData;
            }

            Path csvPath = Paths.get("/app/shared_data", file);
            if (!Files.exists(csvPath)) {
                return stateData;
            }

            List<Map<String, String>> rows = new ArrayList<>();
            try (BufferedReader reader = new BufferedReader(new FileReader(csvPath.toFile()))) {
                String headerLine = reader.readLine();
                if (headerLine == null) return stateData;

                String[] headers = headerLine.split(",");
                String line;
                while ((line = reader.readLine()) != null) {
                    String[] values = line.split(",", -1);
                    Map<String, String> row = new LinkedHashMap<>();
                    for (int i = 0; i < headers.length && i < values.length; i++) {
                        String h = headers[i].replaceAll("^\"|\"$", "");
                        String v = values[i].replaceAll("^\"|\"$", "");
                        row.put(h, v);
                    }
                    rows.add(row);
                }
            }

            payload.put("dataset", rows);
            return objectMapper.writeValueAsString(payload);

        } catch (Exception e) {
            System.err.println("Climate checkpoint enrichment failed: " + e.getMessage());
            return stateData;
        }
    }

    @SuppressWarnings("unchecked")
    private void restoreClimateFile(Map<String, Object> payload) {
        try {
            String action = (String) payload.get("action");
            String file = (String) payload.get("file");
            Object dataset = payload.get("dataset");

            if (!"CLIMATE_READY".equals(action) || file == null || dataset == null) {
                return;
            }

            List<Map<String, Object>> rows = (List<Map<String, Object>>) dataset;
            if (rows.isEmpty()) return;

            StringBuilder csv = new StringBuilder();
            List<String> headers = new ArrayList<>(rows.get(0).keySet());
            csv.append(String.join(",", headers)).append("\n");

            for (Map<String, Object> row : rows) {
                List<String> values = new ArrayList<>();
                for (String h : headers) {
                    Object v = row.get(h);
                    String val = v != null ? v.toString() : "";
                    if (val.contains(",")) val = "\"" + val + "\"";
                    values.add(val);
                }
                csv.append(String.join(",", values)).append("\n");
            }

            Path csvPath = Paths.get("/app/shared_data", file);
            Files.writeString(csvPath, csv.toString());

            payload.remove("dataset");

        } catch (Exception e) {
            System.err.println("Climate file restore failed: " + e.getMessage());
        }
    }
}
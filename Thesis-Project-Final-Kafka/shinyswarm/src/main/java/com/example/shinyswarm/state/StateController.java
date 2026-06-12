package com.example.shinyswarm.state;

import java.security.Principal;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate;

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
public class StateController {

    private final SavedStateRepository savedStateRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final CollaborationSessionRepository sessionRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper; 
    private final SessionStateMonitor sessionStateMonitor;

    public StateController(SavedStateRepository savedStateRepository, 
                           UserRepository userRepository, 
                           ShinyAppRepository shinyAppRepository,
                           CollaborationSessionRepository sessionRepository,
                           KafkaTemplate<String, String> kafkaTemplate,
                           ObjectMapper objectMapper,
                           SessionStateMonitor sessionStateMonitor) {
        this.savedStateRepository = savedStateRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.sessionRepository = sessionRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
        this.sessionStateMonitor = sessionStateMonitor;
    }

    @PostMapping
    public ResponseEntity<?> saveState(@RequestBody SaveStateRequest request, Principal principal) {
        try {
            User user = userRepository.findByUsername(principal.getName())
                    .orElseThrow(() -> new RuntimeException("User not found"));

            // Look up the app by the ID from the request
            ShinyApp app = shinyAppRepository.findById(request.appId())
                    .orElseThrow(() -> new RuntimeException("App not found"));

            String stateData = null;

            // In Kafka mode, we fetch the state payload directly from the Monitor
            if (sessionStateMonitor != null) {
                String kafkaKey = principal.getName();
                if (request.sessionId() != null && !request.sessionId().isEmpty()) {
                    kafkaKey = request.sessionId();
                }
                stateData = sessionStateMonitor.getLatestState(kafkaKey);
            }

            if (stateData == null) {
                return ResponseEntity.status(409).body("No state captured yet. Try performing an action in the app first, then save again.");
            }

            // Store sessionId so other participants can see and restore this checkpoint.
            // Solo-mode keys are not real session UUIDs — exclude them.
            String sessionId = (request.sessionId() != null 
                               && !request.sessionId().isEmpty()
                               && !request.sessionId().startsWith("solo-")) 
                               ? request.sessionId() : null;
            SavedState savedState = new SavedState(request.name(), stateData, user, app, sessionId);
            savedStateRepository.save(savedState);

            return ResponseEntity.ok("State saved successfully");
        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to save state");
        }
    }

    @GetMapping
    public List<SavedStateResponse> getMyStates(
            @RequestParam(required = false) Long appId,
            @RequestParam(required = false) String sessionId,
            Principal principal) {
        
        String username = principal.getName();
        List<SavedState> states;

        if (sessionId != null && !sessionId.isEmpty()) {
            // In a collaboration session: show all checkpoints saved by any participant
            CollaborationSession session = sessionRepository.findById(sessionId).orElse(null);
            if (session == null || session.getParticipants().stream()
                    .noneMatch(p -> p.getUser().getUsername().equals(username))) {
                states = List.of();
            } else {
                states = savedStateRepository.findBySessionIdOrderByCreatedAtDesc(sessionId);
            }
        } else if (appId != null) {
            states = savedStateRepository.findByUser_UsernameAndShinyApp_IdOrderByCreatedAtDesc(username, appId);
        } else {
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
            
            payload.put("sender", "System Restore");
            // Use seconds (not millis) to match R's as.numeric(Sys.time())
            payload.put("timestamp", System.currentTimeMillis() / 1000.0);
            
            String kafkaPayload = objectMapper.writeValueAsString(payload);

            String kafkaKey;
            if (sessionId != null && !sessionId.isEmpty()) {
                kafkaKey = sessionId;
            } else {
                kafkaKey = username; 
            }

            kafkaTemplate.send("output", kafkaKey, kafkaPayload);
            
            return ResponseEntity.ok("State restored");

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to parse state data");
        }
    }
}
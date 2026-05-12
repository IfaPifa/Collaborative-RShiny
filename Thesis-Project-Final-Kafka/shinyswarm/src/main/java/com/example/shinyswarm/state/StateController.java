package com.example.shinyswarm.state;

import java.security.Principal;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate;
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
import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

// DTOs updated to match exactly what AppDataService.ts sends
record SaveStateRequest(Long appId, String name, String sessionId) {}
record SavedStateResponse(Long id, String appName, String name, String stateData, String createdAt) {}

@RestController
@RequestMapping("/api/states")
@CrossOrigin(origins = "http://localhost:4200") 
public class StateController {

    private final SavedStateRepository savedStateRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper; 
    
    // 1. ADD THE KAFKA MONITOR
    private final SessionStateMonitor stateMonitor; 

    public StateController(SavedStateRepository savedStateRepository, 
                           UserRepository userRepository, 
                           ShinyAppRepository shinyAppRepository,
                           KafkaTemplate<String, String> kafkaTemplate,
                           ObjectMapper objectMapper,
                           SessionStateMonitor stateMonitor) { // 2. INJECT IT
        this.savedStateRepository = savedStateRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
        this.stateMonitor = stateMonitor;
    }

    @PostMapping
    public ResponseEntity<?> saveState(@RequestBody SaveStateRequest request, Principal principal) {
        String username = principal.getName();
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));

        ShinyApp app = shinyAppRepository.findById(request.appId())
                .orElseThrow(() -> new RuntimeException("App not found"));

        // 3. DETERMINE THE KAFKA ROUTING KEY
        // In Solo mode, the routing key is the username.
        String kafkaKey = (request.sessionId() != null && !request.sessionId().isEmpty()) 
                ? request.sessionId() 
                : username;

        // 4. FETCH THE LATEST LIVE STATE FROM KAFKA
        String currentState = stateMonitor.getLatestState(kafkaKey);

        if (currentState == null) {
            return ResponseEntity.badRequest().body("No live data available in Kafka to save.");
        }

        // 5. SAVE ACTUAL DATA TO DB
        SavedState newState = new SavedState(request.name(), currentState, user, app);
        savedStateRepository.save(newState);

        return ResponseEntity.ok("State saved successfully");
    }

    @GetMapping
    public List<SavedStateResponse> getMyStates(Principal principal) {
        String username = principal.getName();
        return savedStateRepository.findByUser_UsernameOrderByCreatedAtDesc(username)
                .stream()
                .map(state -> new SavedStateResponse(
                        state.getId(),
                        state.getShinyApp().getName(),
                        state.getName(),
                        state.getStateData(),
                        state.getCreatedAt().toString()
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
        
        if (!state.getUser().getUsername().equals(principal.getName())) {
             return ResponseEntity.status(403).body("Not your state");
        }

        try {
            Map<String, Object> payload = objectMapper.readValue(state.getStateData(), Map.class);
            
            payload.put("sender", "System Restore");
            payload.put("timestamp", System.currentTimeMillis());
            
            String kafkaPayload = objectMapper.writeValueAsString(payload);

            String kafkaKey;
            if (sessionId != null && !sessionId.isEmpty()) {
                kafkaKey = sessionId;
            } else {
                User currentUser = userRepository.findByUsername(principal.getName())
                    .orElseThrow(() -> new RuntimeException("User not found"));
                kafkaKey = currentUser.getUsername(); 
            }

            kafkaTemplate.send("input", kafkaKey, kafkaPayload);
            
            return ResponseEntity.ok("State restored");

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to parse state data");
        }
    }
}
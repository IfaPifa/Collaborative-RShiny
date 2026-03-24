package com.example.shinyswarm.state;

import java.security.Principal;
import java.util.List;
import java.util.Map;
import java.util.stream.Collectors;

import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate; // <-- New Import
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping; // <-- New Import
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

// DTOs
record SaveStateRequest(Long appId, String name, String stateData) {}
record SavedStateResponse(Long id, String appName, String name, String stateData, String createdAt) {}

@RestController
@RequestMapping("/api/states")
@CrossOrigin(origins = "http://localhost:4200") 
public class StateController {

    private final SavedStateRepository savedStateRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    
    // Kafka Components
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final ObjectMapper objectMapper; // For JSON processing

    public StateController(SavedStateRepository savedStateRepository, 
                           UserRepository userRepository, 
                           ShinyAppRepository shinyAppRepository,
                           KafkaTemplate<String, String> kafkaTemplate,
                           ObjectMapper objectMapper) {
        this.savedStateRepository = savedStateRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.kafkaTemplate = kafkaTemplate;
        this.objectMapper = objectMapper;
    }

    @PostMapping
    public ResponseEntity<?> saveState(@RequestBody SaveStateRequest request, Principal principal) {
        String username = principal.getName();
        User user = userRepository.findByUsername(username)
                .orElseThrow(() -> new RuntimeException("User not found"));

        ShinyApp app = shinyAppRepository.findById(request.appId())
                .orElseThrow(() -> new RuntimeException("App not found"));

        SavedState newState = new SavedState(request.name(), request.stateData(), user, app);
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

    // --- NEW ENDPOINT: Restore State via Kafka ---
    @PostMapping("/{id}/restore")
    public ResponseEntity<?> restoreState(
            @PathVariable Long id, 
            @RequestParam(required = false) String sessionId, 
            Principal principal) {

        // 1. Fetch State
        SavedState state = savedStateRepository.findById(id)
                .orElseThrow(() -> new RuntimeException("State not found"));
        
        // 2. Security Check
        if (!state.getUser().getUsername().equals(principal.getName())) {
             return ResponseEntity.status(403).body("Not your state");
        }

        try {
            // 3. Prepare the Payload
            // Read the stored JSON: {"num1": 10, "num2": 20}
            Map<String, Object> payload = objectMapper.readValue(state.getStateData(), Map.class);
            
            // Add metadata so R knows this is a system restore
            payload.put("sender", "System Restore");
            payload.put("timestamp", System.currentTimeMillis());
            
            // Convert back to String: {"num1":10, "num2":20, "sender":"System Restore", ...}
            String kafkaPayload = objectMapper.writeValueAsString(payload);

            // 4. Determine Key (Solo vs Collab)
            String kafkaKey;
            if (sessionId != null && !sessionId.isEmpty()) {
                kafkaKey = sessionId;
            } else {
                User currentUser = userRepository.findByUsername(principal.getName())
                    .orElseThrow(() -> new RuntimeException("User not found"));
                kafkaKey = currentUser.getUsername(); // <--- NEW WAY
            }

            // 5. Send
            kafkaTemplate.send("input", kafkaKey, kafkaPayload);
            
            return ResponseEntity.ok("State restored");

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to parse state data");
        }
    }
}
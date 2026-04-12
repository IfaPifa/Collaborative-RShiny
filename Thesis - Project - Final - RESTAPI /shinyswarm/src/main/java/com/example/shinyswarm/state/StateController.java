package com.example.shinyswarm.state;

import java.security.Principal;
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
import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;
import com.fasterxml.jackson.databind.ObjectMapper;

record SaveStateRequest(Long appId, String name, String sessionId) {}
record SavedStateResponse(Long id, String appName, String name, String stateData, String createdAt) {}

@RestController
@RequestMapping("/api/states")
@CrossOrigin(origins = "http://localhost:4200") 
public class StateController {

    private final SavedStateRepository savedStateRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final StringRedisTemplate redisTemplate;
    private final ObjectMapper objectMapper; 
    private final SessionStateMonitor sessionStateMonitor; 

    public StateController(SavedStateRepository savedStateRepository, 
                           UserRepository userRepository, 
                           ShinyAppRepository shinyAppRepository,
                           StringRedisTemplate redisTemplate,
                           ObjectMapper objectMapper,
                           SessionStateMonitor sessionStateMonitor) {
        this.savedStateRepository = savedStateRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
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
                          
        String latestRealState = sessionStateMonitor.getLatestState(cacheKey);

        // ---> FIX 1: Bridge the Angular "null" ID to the Shiny "solo" ID
        if (latestRealState == null && cacheKey.equals(username)) {
            latestRealState = sessionStateMonitor.getLatestState("solo");
        }

        if (latestRealState == null) {
            return ResponseEntity.badRequest().body("No data generated yet. Run the app analysis first before saving.");
        }

        SavedState newState = new SavedState(request.name(), latestRealState, user, app);
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
            
            String redisPayload = objectMapper.writeValueAsString(payload);

            String cacheKey = (sessionId != null && !sessionId.isEmpty()) ? sessionId : principal.getName();
            
            // ---> FIX 2: Bridge the Angular "null" ID to the Shiny "solo" ID for restores
            if (cacheKey.equals(principal.getName())) {
                cacheKey = "solo";
            }

            redisTemplate.opsForValue().set("session_state:" + cacheKey, redisPayload);
            
            return ResponseEntity.ok("State restored");

        } catch (Exception e) {
            e.printStackTrace();
            return ResponseEntity.internalServerError().body("Failed to parse state data");
        }
    }
}
package com.example.shinyswarm.session;

import java.security.Principal;
import java.util.List;

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;
import org.springframework.web.client.RestTemplate;

import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.app.ShinyAppRepository;
import com.example.shinyswarm.notification.EmailService;
import com.example.shinyswarm.notification.Notification;
import com.example.shinyswarm.notification.NotificationRepository;
import com.example.shinyswarm.state.SavedState;
import com.example.shinyswarm.state.SavedStateRepository;
import com.example.shinyswarm.state.SessionStateMonitor;
import com.example.shinyswarm.user.User;
import com.example.shinyswarm.user.UserRepository;

// --- DTOs ---
record StartSessionRequest(String name, Long appId) {}
record JoinSessionRequest(String sessionId) {}
record SaveSessionRequest(String name) {}
record InviteRequest(String username, String permission) {} 
record UpdatePermissionRequest(String username, String permission) {}
record CalculatorStateRequest(int num1, int num2, String sender) {}

@RestController
@RequestMapping("/api/collab")
@CrossOrigin(origins = "http://localhost:4200")
public class CollaborationController {

    private final CollaborationSessionRepository sessionRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final SavedStateRepository savedStateRepository;
    private final SessionStateMonitor stateMonitor;
    private final NotificationRepository notificationRepository;
    private final EmailService emailService;
    private final SimpMessagingTemplate messagingTemplate;
    
    private final StringRedisTemplate redisTemplate;
    private final RestTemplate restTemplate;

    public CollaborationController(CollaborationSessionRepository sessionRepository,
                                   UserRepository userRepository,
                                   ShinyAppRepository shinyAppRepository,
                                   SavedStateRepository savedStateRepository,
                                   SessionStateMonitor stateMonitor,
                                   StringRedisTemplate redisTemplate,
                                   NotificationRepository notificationRepository,
                                   EmailService emailService,
                                   SimpMessagingTemplate messagingTemplate) {
        this.sessionRepository = sessionRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.savedStateRepository = savedStateRepository;
        this.stateMonitor = stateMonitor;
        this.redisTemplate = redisTemplate;
        this.restTemplate = new RestTemplate();
        this.notificationRepository = notificationRepository;
        this.emailService = emailService;
        this.messagingTemplate = messagingTemplate;
    }

    // ==========================================
    // REST ARCHITECTURE ENDPOINTS
    // ==========================================

    @GetMapping("/{sessionId}/state")
    public ResponseEntity<String> getLiveState(@PathVariable String sessionId) {
        String state = redisTemplate.opsForValue().get("session_state:" + sessionId);
        if (state == null) {
            return ResponseEntity.ok("{}");
        }
        return ResponseEntity.ok(state);
    }

    @PostMapping("/{sessionId}/calculate")
    public ResponseEntity<?> updateCalculatorState(
            @PathVariable String sessionId, 
            @RequestBody String rawJsonPayload) { 
        
        CollaborationSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new RuntimeException("Session not found"));

        // DYNAMIC ROUTING
        String rApiUrl = switch (session.getShinyApp().getName()) {
            case "Advanced Visual Analytics" -> "http://shiny-back-analytics-advanced:8000/calculate";
            case "Visual Analytics" -> "http://shiny-back-analytics:8000/calculate";
            default -> "http://shiny-back:8000/calculate";
        };
        
        try {
            // FIX: Explicitly rebuild the JSON headers so Plumber doesn't ignore the payload!
            org.springframework.http.HttpHeaders headers = new org.springframework.http.HttpHeaders();
            headers.setContentType(org.springframework.http.MediaType.APPLICATION_JSON);
            org.springframework.http.HttpEntity<String> requestEntity = 
                new org.springframework.http.HttpEntity<>(rawJsonPayload, headers);

            // Send the requestEntity instead of the raw string
            ResponseEntity<String> rResponse = restTemplate.postForEntity(rApiUrl, requestEntity, String.class);
            String finalJsonState = rResponse.getBody();
            
            redisTemplate.opsForValue().set("session_state:" + sessionId, finalJsonState);
            return ResponseEntity.ok(finalJsonState);
            
        } catch (Exception e) {
            return ResponseEntity.status(500).body("Error communicating with R backend: " + e.getMessage());
        }
    }

    // ==========================================
    // STANDARD SESSION MANAGEMENT
    // ==========================================

    @GetMapping
    public List<CollaborationSession> getMySessions(Principal principal) {
        return sessionRepository.findByParticipants_User_UsernameAndStatus(principal.getName(), "ACTIVE");
    }

    @PostMapping("/start")
    public ResponseEntity<?> startSession(@RequestBody StartSessionRequest request, Principal principal) {
        User host = userRepository.findByUsername(principal.getName()).orElseThrow();
        ShinyApp app = shinyAppRepository.findById(request.appId()).orElseThrow();
        CollaborationSession session = new CollaborationSession(request.name(), host, app);
        
        // FIX 1: Explicitly add the Host to the participant list so canEdit() returns TRUE
        session.addParticipant(host, SessionPermission.OWNER);
        
        sessionRepository.save(session);
        return ResponseEntity.ok(session);
    }

    @PostMapping("/join")
    public ResponseEntity<?> joinSession(@RequestBody JoinSessionRequest request, Principal principal) {
        String cleanId = request.sessionId().trim();
        User user = userRepository.findByUsername(principal.getName()).orElseThrow();
        CollaborationSession session = sessionRepository.findById(cleanId).orElseThrow();

        if (!"ACTIVE".equalsIgnoreCase(session.getStatus())) {
            return ResponseEntity.badRequest().body("Session is closed");
        }
        session.addParticipant(user, SessionPermission.EDITOR);
        sessionRepository.save(session);
        return ResponseEntity.ok(session);
    }

    @PostMapping("/{sessionId}/save")
    public ResponseEntity<?> saveSessionState(@PathVariable String sessionId, 
                                              @RequestBody SaveSessionRequest request, 
                                              Principal principal) {
        User user = userRepository.findByUsername(principal.getName()).orElseThrow();
        CollaborationSession session = sessionRepository.findById(sessionId).orElseThrow();

        if (!session.canEdit(principal.getName())) {
            return ResponseEntity.status(403).body("Only Owners and Editors can save snapshots.");
        }
        
        String currentState = stateMonitor.getLatestState(sessionId);
        if (currentState == null) {
            return ResponseEntity.badRequest().body("No data available to save.");
        }

        SavedState savedState = new SavedState(request.name(), currentState, user, session.getShinyApp());
        savedStateRepository.save(savedState);
        return ResponseEntity.ok("Session state saved successfully");
    }

    @PostMapping("/{sessionId}/replay")
    public ResponseEntity<?> replayState(@PathVariable String sessionId) {
        return ResponseEntity.ok("State active in Redis. Frontend will pull automatically.");
    }

    @PostMapping("/{sessionId}/restore/{stateId}")
    public ResponseEntity<?> restoreState(@PathVariable String sessionId, @PathVariable Long stateId) {
        SavedState state = savedStateRepository.findById(stateId).orElseThrow();
        redisTemplate.opsForValue().set("session_state:" + sessionId, state.getStateData());
        return ResponseEntity.ok("State restored to Redis");
    }

    @PostMapping("/{sessionId}/invite")
    public ResponseEntity<?> inviteUser(@PathVariable String sessionId, 
                                        @RequestBody InviteRequest request, 
                                        Principal principal) {
        String hostName = principal.getName();
        CollaborationSession session = sessionRepository.findById(sessionId).orElseThrow();
        User guest = userRepository.findByUsername(request.username()).orElseThrow();
        
        SessionPermission assignedPermission = SessionPermission.VIEWER; 
        if (request.permission() != null && !request.permission().isEmpty()) {
            try {
                assignedPermission = SessionPermission.valueOf(request.permission().toUpperCase());
            } catch (IllegalArgumentException e) {
                return ResponseEntity.badRequest().body("Invalid permission level");
            }
        }
        
        session.addParticipant(guest, assignedPermission); 
        sessionRepository.save(session);

        Notification notification = new Notification(guest, hostName + " invited you to '" + session.getName() + "'", sessionId);
        notificationRepository.save(notification);

        if (guest.getEmail() != null && !guest.getEmail().isEmpty()) {
            emailService.sendInviteEmail(guest.getEmail(), hostName, session.getShinyApp().getName(), sessionId);
        }
        return ResponseEntity.ok("Invitation sent");
    }
    
    @GetMapping("/notifications")
    public List<Notification> getNotifications(Principal principal) {
        return notificationRepository.findByRecipient_UsernameAndIsReadFalseOrderByCreatedAtDesc(principal.getName());
    }

    @PostMapping("/notifications/{id}/dismiss")
    public ResponseEntity<?> dismissNotification(@PathVariable Long id) {
        Notification n = notificationRepository.findById(id).orElseThrow();
        n.markAsRead();
        notificationRepository.save(n);
        return ResponseEntity.ok("Dismissed");
    }

    @PutMapping("/{sessionId}/permissions")
    public ResponseEntity<?> updatePermission(@PathVariable String sessionId,
                                              @RequestBody UpdatePermissionRequest request,
                                              Principal principal) {
        
        CollaborationSession session = sessionRepository.findById(sessionId).orElseThrow();

        if (!session.getHost().getUsername().equals(principal.getName())) {
            return ResponseEntity.status(403).body("Only the session owner can change permissions.");
        }

        SessionPermission newPerm;
        try {
            newPerm = SessionPermission.valueOf(request.permission().toUpperCase());
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Invalid permission level");
        }

        session.updateParticipantPermission(request.username(), newPerm);
        sessionRepository.save(session);

        String wsMessage = String.format("{\"username\":\"%s\", \"type\":\"ROLE_UPDATE\", \"sessionId\":\"%s\"}", request.username(), sessionId);
        messagingTemplate.convertAndSend("/topic/presence/" + sessionId, wsMessage);

        return ResponseEntity.ok("Permission updated successfully");
    }
}
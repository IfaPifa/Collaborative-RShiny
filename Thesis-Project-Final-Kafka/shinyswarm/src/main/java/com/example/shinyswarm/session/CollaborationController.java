package com.example.shinyswarm.session;

import java.security.Principal;
import java.util.List;

import org.springframework.http.ResponseEntity;
import org.springframework.kafka.core.KafkaTemplate;
import org.springframework.messaging.simp.SimpMessagingTemplate;
import org.springframework.web.bind.annotation.CrossOrigin;
import org.springframework.web.bind.annotation.GetMapping;
import org.springframework.web.bind.annotation.PathVariable;
import org.springframework.web.bind.annotation.PostMapping;
import org.springframework.web.bind.annotation.PutMapping;
import org.springframework.web.bind.annotation.RequestBody;
import org.springframework.web.bind.annotation.RequestMapping;
import org.springframework.web.bind.annotation.RestController;

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

@RestController
@RequestMapping("/api/collab")
@CrossOrigin(origins = "http://localhost:4200")
public class CollaborationController {

    private final CollaborationSessionRepository sessionRepository;
    private final UserRepository userRepository;
    private final ShinyAppRepository shinyAppRepository;
    private final SavedStateRepository savedStateRepository;
    private final SessionStateMonitor stateMonitor;
    private final KafkaTemplate<String, String> kafkaTemplate;
    private final NotificationRepository notificationRepository;
    private final EmailService emailService;
    private final SimpMessagingTemplate messagingTemplate;
    

    public CollaborationController(CollaborationSessionRepository sessionRepository,
                                   UserRepository userRepository,
                                   ShinyAppRepository shinyAppRepository,
                                   SavedStateRepository savedStateRepository,
                                   SessionStateMonitor stateMonitor,
                                   KafkaTemplate<String, String> kafkaTemplate,
                                   NotificationRepository notificationRepository,
                                   EmailService emailService,
                                   SimpMessagingTemplate messagingTemplate) {
        this.sessionRepository = sessionRepository;
        this.userRepository = userRepository;
        this.shinyAppRepository = shinyAppRepository;
        this.savedStateRepository = savedStateRepository;
        this.stateMonitor = stateMonitor;
        this.kafkaTemplate = kafkaTemplate;
        this.notificationRepository = notificationRepository;
        this.emailService = emailService;
        this.messagingTemplate = messagingTemplate;
    }

    // 1. List active sessions for user
    @GetMapping
    public List<CollaborationSession> getMySessions(Principal principal) {
        // Updated to use the new method name with "_User_"
        return sessionRepository.findByParticipants_User_UsernameAndStatus(principal.getName(), "ACTIVE");
    }

    // 2. Start session
    @PostMapping("/start")
    public ResponseEntity<?> startSession(@RequestBody StartSessionRequest request, Principal principal) {
        User host = userRepository.findByUsername(principal.getName())
                .orElseThrow(() -> new RuntimeException("User not found"));

        ShinyApp app = shinyAppRepository.findById(request.appId())
                .orElseThrow(() -> new RuntimeException("App not found"));

        CollaborationSession session = new CollaborationSession(request.name(), host, app);
        sessionRepository.save(session);
        return ResponseEntity.ok(session);
    }

    // 3. Join session
    @PostMapping("/join")
    public ResponseEntity<?> joinSession(@RequestBody JoinSessionRequest request, Principal principal) {
        String cleanId = request.sessionId().trim();
        User user = userRepository.findByUsername(principal.getName())
                .orElseThrow(() -> new RuntimeException("User not found"));

        CollaborationSession session = sessionRepository.findById(cleanId)
                .orElseThrow(() -> new RuntimeException("Session not found"));

        if (!"ACTIVE".equalsIgnoreCase(session.getStatus())) {
            return ResponseEntity.badRequest().body("Session is closed");
        }

        session.addParticipant(user, SessionPermission.EDITOR);
        sessionRepository.save(session);
        return ResponseEntity.ok(session);
    }

    // 4. Save Session State
    @PostMapping("/{sessionId}/save")
    public ResponseEntity<?> saveSessionState(@PathVariable String sessionId, 
                                              @RequestBody SaveSessionRequest request, 
                                              Principal principal) {
        User user = userRepository.findByUsername(principal.getName())
                .orElseThrow(() -> new RuntimeException("User not found"));

        CollaborationSession session = sessionRepository.findById(sessionId)
        .orElseThrow(() -> new RuntimeException("Session not found"));

        // --- SECURITY CHECK ---
        if (!session.canEdit(principal.getName())) {
            return ResponseEntity.status(403).body("Only Owners and Editors can save snapshots.");
        }
        // --------------------------
        String currentState = stateMonitor.getLatestState(sessionId);
        if (currentState == null) {
            return ResponseEntity.badRequest().body("No data available to save.");
        }

        SavedState savedState = new SavedState(request.name(), currentState, user, session.getShinyApp());
        savedStateRepository.save(savedState);
        return ResponseEntity.ok("Session state saved successfully");
    }

    // 5. Replay (Auto-load)
    @PostMapping("/{sessionId}/replay")
    public ResponseEntity<?> replayState(@PathVariable String sessionId) {
        String cachedState = stateMonitor.getLatestState(sessionId);
        if (cachedState != null) {
            kafkaTemplate.send("input", sessionId, cachedState);
            return ResponseEntity.ok("State replayed");
        }
        return ResponseEntity.ok("No live state to replay");
    }

    // 6. Restore (Load Checkpoint)
    @PostMapping("/{sessionId}/restore/{stateId}")
    public ResponseEntity<?> restoreState(@PathVariable String sessionId, @PathVariable Long stateId) {
        SavedState state = savedStateRepository.findById(stateId)
                .orElseThrow(() -> new RuntimeException("State not found"));
        kafkaTemplate.send("input", sessionId, state.getStateData());
        return ResponseEntity.ok("State restored");
    }

    // 7. Invite User
    @PostMapping("/{sessionId}/invite")
    public ResponseEntity<?> inviteUser(@PathVariable String sessionId, 
                                        @RequestBody InviteRequest request, 
                                        Principal principal) {
        
        String hostName = principal.getName();
        
        // 1. Fetch the Session FIRST
        CollaborationSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new RuntimeException("Session not found"));

        // 2. Fetch the Guest
        User guest = userRepository.findByUsername(request.username())
                .orElseThrow(() -> new RuntimeException("User not found"));
        
        // --- Parse the permission from the request ---
        SessionPermission assignedPermission = SessionPermission.VIEWER; // Default fallback
        if (request.permission() != null && !request.permission().isEmpty()) {
            try {
                assignedPermission = SessionPermission.valueOf(request.permission().toUpperCase());
            } catch (IllegalArgumentException e) {
                return ResponseEntity.badRequest().body("Invalid permission level");
            }
        }
        
        // 3. Use the dynamically assigned permission instead of hardcoding VIEWER
        session.addParticipant(guest, assignedPermission); 
        sessionRepository.save(session);

        // 4. Create In-App Notification
        Notification notification = new Notification(guest, hostName + " invited you to '" + session.getName() + "'", sessionId);
        notificationRepository.save(notification);

        // 5. Send Email
        if (guest.getEmail() != null && !guest.getEmail().isEmpty()) {
            emailService.sendInviteEmail(guest.getEmail(), hostName, session.getShinyApp().getName(), sessionId);
        } else {
            System.out.println("User " + guest.getUsername() + " has no email. Skipping.");
        }

        return ResponseEntity.ok("Invitation sent");
    }
    
    // 8. Inbox
    @GetMapping("/notifications")
    public List<Notification> getNotifications(Principal principal) {
        return notificationRepository.findByRecipient_UsernameAndIsReadFalseOrderByCreatedAtDesc(principal.getName());
    }

    // 9. Dismiss
    @PostMapping("/notifications/{id}/dismiss")
    public ResponseEntity<?> dismissNotification(@PathVariable Long id) {
        Notification n = notificationRepository.findById(id).orElseThrow();
        n.markAsRead();
        notificationRepository.save(n);
        return ResponseEntity.ok("Dismissed");
    }

    // 10. Change User Permission (Real-Time)
    @PutMapping("/{sessionId}/permissions")
    public ResponseEntity<?> updatePermission(@PathVariable String sessionId,
                                              @RequestBody UpdatePermissionRequest request,
                                              Principal principal) {
        
        CollaborationSession session = sessionRepository.findById(sessionId)
                .orElseThrow(() -> new RuntimeException("Session not found"));

        // Security Check: Only the Host (Owner) can change permissions
        if (!session.getHost().getUsername().equals(principal.getName())) {
            return ResponseEntity.status(403).body("Only the session owner can change permissions.");
        }

        SessionPermission newPerm;
        try {
            newPerm = SessionPermission.valueOf(request.permission().toUpperCase());
        } catch (IllegalArgumentException e) {
            return ResponseEntity.badRequest().body("Invalid permission level");
        }

        // 1. Update Database
        session.updateParticipantPermission(request.username(), newPerm);
        sessionRepository.save(session);

        // 2. Broadcast to Angular UI via WebSocket
        // We send a custom presence message of type 'ROLE_UPDATE'
        String wsMessage = String.format("{\"username\":\"%s\", \"type\":\"ROLE_UPDATE\", \"sessionId\":\"%s\"}", request.username(), sessionId);
        messagingTemplate.convertAndSend("/topic/presence/" + sessionId, wsMessage);

        // 3. Broadcast to R-Shiny via Kafka
        // We send a 'SYSTEM' message that the R script will catch
        String kafkaMsg = String.format("{\"type\":\"SYSTEM\", \"targetUser\":\"%s\", \"newRole\":\"%s\"}", request.username(), newPerm.name());
        kafkaTemplate.send("output", sessionId, kafkaMsg);

        return ResponseEntity.ok("Permission updated successfully");
    }

    
}
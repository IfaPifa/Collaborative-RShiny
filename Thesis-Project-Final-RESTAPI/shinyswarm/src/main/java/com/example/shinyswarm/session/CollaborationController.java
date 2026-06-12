package com.example.shinyswarm.session;

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

import org.springframework.data.redis.core.StringRedisTemplate;
import org.springframework.http.ResponseEntity;
import org.springframework.http.HttpEntity;
import org.springframework.http.HttpHeaders;
import org.springframework.http.MediaType;
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

import com.fasterxml.jackson.databind.ObjectMapper;

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
    private final NotificationRepository notificationRepository;
    private final EmailService emailService;
    private final SimpMessagingTemplate messagingTemplate;
    
    private final StringRedisTemplate redisTemplate;
    private final RestTemplate restTemplate;
    private final ObjectMapper objectMapper;

    // App name -> Plumber container hostname mapping
    private static final Map<String, String> APP_ROUTES = Map.of(
        "Calculator",      "http://shiny-back:8000/calculate",
        "Analytics",        "http://shiny-back-analytics:8000/state",
        "Advanced",         "http://shiny-back-analytics-advanced:8000/state",
        "DataExchange",     "http://shiny-back-csv:8000/state",
        "ClimateAnomaly",   "http://shiny-back-csv-advanced:8000/state",
        "MonteCarlo",       "http://shiny-back-mc:8000/state",
        "Geospatial",       "http://shiny-back-map:8000/state",
        "MLTrainer",        "http://shiny-back-ml:8000/state",
        "Honeybee",         "http://shiny-back-beehave:8000/state"
    );

    public CollaborationController(CollaborationSessionRepository sessionRepository,
                                   UserRepository userRepository,
                                   ShinyAppRepository shinyAppRepository,
                                   SavedStateRepository savedStateRepository,
                                   SessionStateMonitor stateMonitor,
                                   StringRedisTemplate redisTemplate,
                                   NotificationRepository notificationRepository,
                                   EmailService emailService,
                                   SimpMessagingTemplate messagingTemplate,
                                   ObjectMapper objectMapper) {
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
        this.objectMapper = objectMapper;
    }

    // ==========================================
    // GENERIC REST STATE RELAY ENDPOINT
    // ==========================================

    @GetMapping("/{sessionId}/state")
    public ResponseEntity<String> getLiveState(@PathVariable String sessionId) {
        String state = redisTemplate.opsForValue().get("session_state:" + sessionId);
        if (state == null) {
            return ResponseEntity.ok("{}");
        }
        return ResponseEntity.ok(state);
    }

    /**
     * Generic state relay: R Shiny POSTs state here, Java routes it to the
     * correct Plumber backend based on the "appName" field in the JSON body,
     * then stores the Plumber response in Redis for polling.
     */
    @PostMapping("/{sessionId}/state")
    public ResponseEntity<?> relayState(
            @PathVariable String sessionId,
            @RequestBody String rawJson) {

        try {
            // Parse the appName from the raw JSON
            Map<String, Object> body = objectMapper.readValue(rawJson, Map.class);
            String appName = (String) body.getOrDefault("appName", "");
            String sender = (String) body.getOrDefault("sender", "anonymous");

            // Permission check for collaborative sessions
            if (!"solo".equals(sessionId)) {
                sessionRepository.findById(sessionId).ifPresent(session -> {
                    if (!session.canEdit(sender)) {
                        throw new RuntimeException("Read-only users cannot update state.");
                    }
                });
            }

            // Route to the correct Plumber backend
            String plumberUrl = APP_ROUTES.get(appName);
            if (plumberUrl == null) {
                return ResponseEntity.badRequest().body("Unknown appName: " + appName);
            }

            // Forward the full JSON body to Plumber
            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<String> request = new HttpEntity<>(rawJson, headers);

            ResponseEntity<String> rResponse = restTemplate.postForEntity(plumberUrl, request, String.class);
            String finalJsonState = rResponse.getBody();

            // Store in Redis for polling
            redisTemplate.opsForValue().set("session_state:" + sessionId, finalJsonState);
            return ResponseEntity.ok(finalJsonState);

        } catch (Exception e) {
            return ResponseEntity.status(500).body("State relay error: " + e.getMessage());
        }
    }

    // ==========================================
    // LEGACY CALCULATOR ENDPOINT (kept for backward compatibility)
    // ==========================================

    @PostMapping("/{sessionId}/calculate")
    public ResponseEntity<?> updateCalculatorState(
            @PathVariable String sessionId,
            @RequestBody String rawJson) {

        try {
            Map<String, Object> body = objectMapper.readValue(rawJson, Map.class);
            String sender = (String) body.getOrDefault("sender", "anonymous");

            if (!"solo".equals(sessionId)) {
                CollaborationSession session = sessionRepository.findById(sessionId)
                        .orElseThrow(() -> new RuntimeException("Session not found"));
                if (!session.canEdit(sender)) {
                    return ResponseEntity.status(403).body("Read-only users cannot trigger calculations.");
                }
            }

            String rApiUrl = "http://shiny-back:8000/calculate";

            HttpHeaders headers = new HttpHeaders();
            headers.setContentType(MediaType.APPLICATION_JSON);
            HttpEntity<String> request = new HttpEntity<>(rawJson, headers);

            ResponseEntity<String> rResponse = restTemplate.postForEntity(rApiUrl, request, String.class);
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

        // Enrich Climate Anomaly checkpoints with the processed CSV data
        currentState = enrichClimateCheckpoint(currentState);

        SavedState savedState = new SavedState(request.name(), currentState, user, session.getShinyApp(), sessionId);
        savedStateRepository.save(savedState);
        return ResponseEntity.ok("Session state saved successfully");
    }

    @PostMapping("/{sessionId}/replay")
    public ResponseEntity<?> replayState(@PathVariable String sessionId) {
        return ResponseEntity.ok("State active in Redis. Frontend will pull automatically.");
    }

    @PostMapping("/{sessionId}/restore/{stateId}")
    public ResponseEntity<?> restoreState(@PathVariable String sessionId, @PathVariable Long stateId, Principal principal) {
        SavedState state = savedStateRepository.findById(stateId).orElseThrow();

        // Allow restore if caller is the owner OR a participant of this session
        String username = principal.getName();
        boolean isOwner = state.getUser().getUsername().equals(username);
        boolean isParticipant = false;

        if (!isOwner) {
            CollaborationSession session = sessionRepository.findById(sessionId).orElse(null);
            if (session != null) {
                isParticipant = session.getParticipants().stream()
                        .anyMatch(p -> p.getUser().getUsername().equals(username));
            }
        }

        if (!isOwner && !isParticipant) {
            return ResponseEntity.status(403).body("You do not have access to this checkpoint");
        }

        try {
            Map<String, Object> payload = objectMapper.readValue(state.getStateData(), Map.class);

            // Write embedded Climate Anomaly data back to the shared volume
            restoreClimateFile(payload);

            payload.put("sender", "System Restore");
            // Use seconds (not millis) to match R's as.numeric(Sys.time())
            payload.put("timestamp", System.currentTimeMillis() / 1000.0);
            String updatedPayload = objectMapper.writeValueAsString(payload);
            redisTemplate.opsForValue().set("session_state:" + sessionId, updatedPayload);
        } catch (Exception e) {
            // Fallback: write raw state data if JSON parsing fails
            redisTemplate.opsForValue().set("session_state:" + sessionId, state.getStateData());
        }

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

    /**
     * At save time: if the state is a CLIMATE_READY message with a file reference,
     * read the CSV from the shared volume and embed it in the JSON so the
     * checkpoint is self-contained.
     */
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

    /**
     * At restore time: if the checkpoint has an embedded "dataset", write it
     * back to the shared volume as the referenced CSV, then remove "dataset"
     * from the payload so the Shiny app reads from disk as usual.
     */
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

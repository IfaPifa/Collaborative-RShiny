package com.example.shinyswarm.presence;

import org.springframework.messaging.handler.annotation.DestinationVariable;
import org.springframework.messaging.handler.annotation.MessageMapping;
import org.springframework.messaging.handler.annotation.Payload;
import org.springframework.messaging.handler.annotation.SendTo;
import org.springframework.messaging.simp.SimpMessageHeaderAccessor;
import org.springframework.stereotype.Controller;

import com.example.shinyswarm.session.CollaborationSessionRepository; // IMPORT THIS

record PresenceMessage(String username, String type, String sessionId) {} 

@Controller
public class PresenceController {

    private final CollaborationSessionRepository sessionRepository;

    // Inject the database repository
    public PresenceController(CollaborationSessionRepository sessionRepository) {
        this.sessionRepository = sessionRepository;
    }

    @MessageMapping("/presence.join/{sessionId}")
    @SendTo("/topic/presence/{sessionId}")
    public PresenceMessage joinSession(
            @Payload PresenceMessage message, 
            @DestinationVariable String sessionId,
            SimpMessageHeaderAccessor headerAccessor
    ) {
        headerAccessor.getSessionAttributes().put("username", message.username());
        headerAccessor.getSessionAttributes().put("sessionId", sessionId);

        // --- UPDATE DB: User is now ONLINE ---
        sessionRepository.findById(sessionId).ifPresent(session -> {
            session.setParticipantOnline(message.username(), true);
            sessionRepository.save(session);
        });

        return message; 
    }

    @MessageMapping("/presence.leave/{sessionId}")
    @SendTo("/topic/presence/{sessionId}")
    public PresenceMessage leaveSession(@Payload PresenceMessage message, @DestinationVariable String sessionId) {
        
        // --- 1. LOG RECEIVED MESSAGE ---
        System.out.println("[BACKEND] 🔴 Received LEAVE request for user: " + message.username() + " in session: " + sessionId);

        try {
            sessionRepository.findById(sessionId).ifPresent(session -> {
                session.setParticipantOnline(message.username(), false);
                sessionRepository.save(session);
                System.out.println("[BACKEND] 💾 Successfully updated database: " + message.username() + " is now offline.");
            });
        } catch (Exception e) {
            System.err.println("[BACKEND] ❌ Database error during leave: " + e.getMessage());
        }

        System.out.println("[BACKEND] 📢 Broadcasting LEAVE message to topic.");
        return message; 
    }
}
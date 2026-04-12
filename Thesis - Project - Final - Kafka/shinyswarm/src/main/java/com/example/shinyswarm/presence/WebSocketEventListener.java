package com.example.shinyswarm.presence;

import org.springframework.context.event.EventListener;
import org.springframework.messaging.simp.SimpMessageSendingOperations;
import org.springframework.messaging.simp.stomp.StompHeaderAccessor;
import org.springframework.stereotype.Component;
import org.springframework.web.socket.messaging.SessionDisconnectEvent;

import com.example.shinyswarm.session.CollaborationSessionRepository; // IMPORT THIS

@Component
public class WebSocketEventListener {

    private final SimpMessageSendingOperations messagingTemplate;
    private final CollaborationSessionRepository sessionRepository;

    public WebSocketEventListener(SimpMessageSendingOperations messagingTemplate, CollaborationSessionRepository sessionRepository) {
        this.messagingTemplate = messagingTemplate;
        this.sessionRepository = sessionRepository;
    }

    @EventListener
    public void handleWebSocketDisconnectListener(SessionDisconnectEvent event) {
        StompHeaderAccessor headerAccessor = StompHeaderAccessor.wrap(event.getMessage());
        
        String username = (String) headerAccessor.getSessionAttributes().get("username");
        String sessionId = (String) headerAccessor.getSessionAttributes().get("sessionId");

        if (username != null && sessionId != null) {
            
            // --- UPDATE DB: User is now OFFLINE (Hard Exit) ---
            sessionRepository.findById(sessionId).ifPresent(session -> {
                session.setParticipantOnline(username, false);
                sessionRepository.save(session);
            });

            PresenceMessage leaveMessage = new PresenceMessage(username, "LEAVE", sessionId);
            messagingTemplate.convertAndSend("/topic/presence/" + sessionId, leaveMessage);
        }
    }
}
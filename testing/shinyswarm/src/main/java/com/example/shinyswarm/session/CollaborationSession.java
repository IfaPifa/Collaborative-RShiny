package com.example.shinyswarm.session;

import java.time.LocalDateTime;
import java.util.HashSet;
import java.util.Set;
import java.util.UUID;

import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.user.User;
import com.fasterxml.jackson.annotation.JsonIgnoreProperties;

import jakarta.persistence.CascadeType;
import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.OneToMany;
import jakarta.persistence.Table;

@Entity
@Table(name = "collaboration_sessions")
public class CollaborationSession {

    @Id
    private String id; // This UUID is the "Kafka Key"

    @Column(nullable = false)
    private String name; // e.g., "Team Brainstorm"

    @Column(nullable = false)
    private String status; // ACTIVE, CLOSED

    @Column(nullable = false)
    private LocalDateTime createdAt;

    // --- Relationships ---

    // The Host (Owner)
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "host_id", nullable = false)
    @JsonIgnoreProperties({"password", "authorities"}) // Don't leak internals
    private User host;

    // The App being used
    @ManyToOne(fetch = FetchType.EAGER)
    @JoinColumn(name = "shiny_app_id", nullable = false)
    private ShinyApp shinyApp;

    // The Participants (User + Permission)
    @OneToMany(mappedBy = "session", cascade = CascadeType.ALL, orphanRemoval = true, fetch = FetchType.EAGER)
    private Set<SessionParticipant> participants = new HashSet<>();

    // --- Constructors ---

    public CollaborationSession() {}

    public CollaborationSession(String name, User host, ShinyApp shinyApp) {
        this.id = UUID.randomUUID().toString(); // Auto-generate "Room Key"
        this.name = name;
        this.host = host;
        this.shinyApp = shinyApp;
        this.status = "ACTIVE";
        this.createdAt = LocalDateTime.now();
        this.addParticipant(host, SessionPermission.OWNER);
    }

    // --- Getters & Setters ---
    public String getId() { return id; }
    public String getName() { return name; }
    public String getStatus() { return status; }
    public void setStatus(String status) { this.status = status; }
    public User getHost() { return host; }
    public ShinyApp getShinyApp() { return shinyApp; }
    public Set<SessionParticipant> getParticipants() {
        return participants;
    }
    public Set<User> getParticipantUsers() {
        return participants.stream()
        .map(SessionParticipant::getUser)
        .collect(java.util.stream.Collectors.toSet());
    }
    
    public void addParticipant(User user, SessionPermission permission) {
        // Check if the user is already in the participants list
        boolean alreadyExists = this.participants.stream()
            .anyMatch(p -> p.getUser().getUsername().equals(user.getUsername()));
            
        // Only add them to the database if they aren't already there
        if (!alreadyExists) {
            SessionParticipant participant = new SessionParticipant(this, user, permission);
            this.participants.add(participant);
        }
    }

    // Helper to check if a user has write access
    public boolean canEdit(String username) {
        return participants.stream()
            .anyMatch(p -> p.getUser().getUsername().equals(username) && 
                     (p.getPermission() == SessionPermission.EDITOR || p.getPermission() == SessionPermission.OWNER));  
    }

    public void updateParticipantPermission(String username, SessionPermission newPermission) {
        this.participants.stream()
            .filter(p -> p.getUser().getUsername().equals(username))
            .findFirst()
            .ifPresent(p -> p.setPermission(newPermission));
    }

    public void setParticipantOnline(String username, boolean online) {
        this.participants.stream()
            .filter(p -> p.getUser().getUsername().equals(username))
            .findFirst()
            .ifPresent(p -> p.setOnline(online));
    }
}
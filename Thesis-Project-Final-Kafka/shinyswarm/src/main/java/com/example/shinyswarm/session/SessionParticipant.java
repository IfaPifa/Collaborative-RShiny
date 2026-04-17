// src/main/java/com/example/shinyswarm/session/SessionParticipant.java
package com.example.shinyswarm.session;

import com.example.shinyswarm.user.User;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.EnumType;
import jakarta.persistence.Enumerated;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "session_participants")
public class SessionParticipant {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @ManyToOne
    @JoinColumn(name = "session_id", nullable = false)
    private CollaborationSession session;

    @ManyToOne
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @Enumerated(EnumType.STRING)
    @Column(nullable = false)
    private SessionPermission permission;

    @Column(nullable = false)
    private boolean isOnline = true;

    // Constructors, Getters, Setters
    public SessionParticipant() {}

    public SessionParticipant(CollaborationSession session, User user, SessionPermission permission) {
        this.session = session;
        this.user = user;
        this.permission = permission;
    }

    public void setPermission(SessionPermission permission) {
        this.permission = permission;
    }

    public User getUser() { return user; }
    public SessionPermission getPermission() { return permission; }

    public boolean isOnline() { return isOnline; }
    public void setOnline(boolean online) { this.isOnline = online; }
    
}
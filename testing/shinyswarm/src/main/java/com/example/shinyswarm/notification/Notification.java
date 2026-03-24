package com.example.shinyswarm.notification;

import java.time.LocalDateTime;

import com.example.shinyswarm.user.User; // Import this
import com.fasterxml.jackson.annotation.JsonIgnore;

import jakarta.persistence.Column;
import jakarta.persistence.Entity;
import jakarta.persistence.FetchType;
import jakarta.persistence.GeneratedValue;
import jakarta.persistence.GenerationType;
import jakarta.persistence.Id;
import jakarta.persistence.JoinColumn;
import jakarta.persistence.ManyToOne;
import jakarta.persistence.Table;

@Entity
@Table(name = "notifications")
public class Notification {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String message;

    @Column(nullable = false)
    private String sessionId;

    private boolean isRead = false;
    private LocalDateTime createdAt;

    // --- ADD @JsonIgnore HERE ---
    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "recipient_id", nullable = false)
    @JsonIgnore
    private User recipient;

    public Notification() {}

    public Notification(User recipient, String message, String sessionId) {
        this.recipient = recipient;
        this.message = message;
        this.sessionId = sessionId;
        this.createdAt = LocalDateTime.now();
    }

    // Getters
    public Long getId() { return id; }
    public String getMessage() { return message; }
    public String getSessionId() { return sessionId; }
    public boolean isRead() { return isRead; } // Jackson sees this as "read": false
    public LocalDateTime getCreatedAt() { return createdAt; }
    public User getRecipient() { return recipient; }
    
    public void markAsRead() { this.isRead = true; }
}
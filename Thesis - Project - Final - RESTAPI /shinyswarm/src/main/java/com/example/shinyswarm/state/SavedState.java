package com.example.shinyswarm.state;

import java.time.LocalDateTime;

import com.example.shinyswarm.app.ShinyApp;
import com.example.shinyswarm.user.User;

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
@Table(name = "saved_states")
public class SavedState {

    @Id
    @GeneratedValue(strategy = GenerationType.IDENTITY)
    private Long id;

    @Column(nullable = false)
    private String name; // e.g., "My Monday Analysis"

    // We store the state as a raw JSON string. 
    // Example: "{\"num1\": 10, \"num2\": 20}"
    @Column(columnDefinition = "TEXT", nullable = false)
    private String stateData; 

    @Column(nullable = false)
    private LocalDateTime createdAt;

    // --- Relationships ---

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "user_id", nullable = false)
    private User user;

    @ManyToOne(fetch = FetchType.LAZY)
    @JoinColumn(name = "shiny_app_id", nullable = false)
    private ShinyApp shinyApp;

    // --- Constructors ---

    public SavedState() {}

    public SavedState(String name, String stateData, User user, ShinyApp shinyApp) {
        this.name = name;
        this.stateData = stateData;
        this.user = user;
        this.shinyApp = shinyApp;
        this.createdAt = LocalDateTime.now();
    }

    // --- Getters ---
    public Long getId() { return id; }
    public String getName() { return name; }
    public String getStateData() { return stateData; }
    public LocalDateTime getCreatedAt() { return createdAt; }
    public User getUser() { return user; }
    public ShinyApp getShinyApp() { return shinyApp; }
}
package com.example.shinyswarm.state;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SavedStateRepository extends JpaRepository<SavedState, Long> {
    
    // Fallback: Fetch all saved states belonging to a specific username
    List<SavedState> findByUser_UsernameOrderByCreatedAtDesc(String username);

    // NEW: Fetch saved states belonging to a specific username AND a specific App ID
    List<SavedState> findByUser_UsernameAndShinyApp_IdOrderByCreatedAtDesc(String username, Long appId);
}
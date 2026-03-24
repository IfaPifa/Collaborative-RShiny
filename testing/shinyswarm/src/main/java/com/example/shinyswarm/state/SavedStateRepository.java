package com.example.shinyswarm.state;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface SavedStateRepository extends JpaRepository<SavedState, Long> {
    
    // Fetch all saved states belonging to a specific username
    // This allows us to show the user ONLY their own saves.
    List<SavedState> findByUser_UsernameOrderByCreatedAtDesc(String username);
}
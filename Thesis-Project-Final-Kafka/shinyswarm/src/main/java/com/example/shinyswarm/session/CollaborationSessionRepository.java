package com.example.shinyswarm.session;

import java.util.List;

import org.springframework.data.jpa.repository.JpaRepository;

public interface CollaborationSessionRepository extends JpaRepository<CollaborationSession, String> {

    List<CollaborationSession> findByParticipants_User_UsernameAndStatus(String username, String status);
}
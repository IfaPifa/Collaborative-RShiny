package com.example.shinyswarm.notification;

import org.springframework.data.jpa.repository.JpaRepository;
import java.util.List;

public interface NotificationRepository extends JpaRepository<Notification, Long> {
    // Find unread messages for a specific user, newest first
    List<Notification> findByRecipient_UsernameAndIsReadFalseOrderByCreatedAtDesc(String username);
}
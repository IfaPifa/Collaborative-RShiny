package com.example.shinyswarm.notification;

import org.springframework.mail.SimpleMailMessage;
import org.springframework.mail.javamail.JavaMailSender;
import org.springframework.scheduling.annotation.Async;
import org.springframework.stereotype.Service;

@Service
public class EmailService {

    private final JavaMailSender mailSender;

    public EmailService(JavaMailSender mailSender) {
        this.mailSender = mailSender;
    }

    @Async // Run in background so the UI doesn't freeze
    public void sendInviteEmail(String toEmail, String hostName, String appName, String sessionId) {
        try {
            SimpleMailMessage message = new SimpleMailMessage();
            message.setFrom("shinyswarm@gmail.com");
            message.setTo("gunjaca.iva@gmail.com");
            message.setSubject("ShinySwarm Invite: " + hostName + " needs you!");
            
            message.setText(String.format(
                "Hello!\n\n" +
                "%s has invited you to collaborate on '%s'.\n\n" +
                "Session ID: %s\n\n" +
                "Log in to ShinySwarm to join immediately.\n",
                hostName, appName, sessionId
            ));

            mailSender.send(message);
            System.out.println("EMAIL SENT to " + toEmail);
        } catch (Exception e) {
            System.err.println("FAILED TO SEND EMAIL: " + e.getMessage());
        }
    }
}